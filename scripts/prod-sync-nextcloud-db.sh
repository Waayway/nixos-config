#!/usr/bin/env bash
# Copy old Main's Nextcloud database into VM 100's (prod) nextcloud-db: a fresh dump
# from Main, then drop, recreate and import on prod.
#
# Two modes:
#   Cutover (Task 8): put Main in maintenance mode first
#     (`docker exec -u www-data nextcloud-app php occ maintenance:mode --on` on Main),
#     then run this script. It refuses to run while Main is not in maintenance mode.
#   Test copy (Task 5): ALLOW_LIVE_MAIN=1 scripts/prod-sync-nextcloud-db.sh
#     Main keeps serving; everything written on Main after the snapshot is missing
#     from prod's copy. Never use this for the cutover.
#
# Runs from atlas (or any machine with SSH to pve and both VMs; prod has no key for
# Main): the dump streams Main -> here -> prod. Main is only read
# (`--single-transaction`, a consistent snapshot). Passwords stay inside the
# containers (MYSQL_PWD from their own environment), never in argv.
#
# On prod the app is stopped while the database is replaced. The dump lands in a
# root-only file first and is checked (gzip, mariadb-dump's completion line) before
# the database is touched; the file is removed whatever happens. If the import fails
# after the DROP, /var/lib/prod/nextcloud/SYNC-FAILED stays behind: the app (and
# cron) units refuse to start while it exists (nextcloud.nix). Do not start the app
# by hand; rerun this script until it succeeds (that removes the marker).
#
# Usage: [ALLOW_LIVE_MAIN=1] scripts/prod-sync-nextcloud-db.sh
#   MAIN, PROD, JUMP override the SSH targets (defaults below).
set -euo pipefail

MAIN=${MAIN:-goedenaam@10.0.10.108}
PROD=${PROD:-prod@10.0.10.100}
JUMP=${JUMP:-pve}

ssh_() { ssh -o BatchMode=yes -o ConnectTimeout=15 -J "$JUMP" "$@"; }

part=/var/lib/prod/nextcloud/sync-dump.sql.gz.part

echo "Main: checking maintenance mode"
mode=$(ssh_ "$MAIN" 'docker exec -u www-data nextcloud-app php occ maintenance:mode' </dev/null)
case "$mode" in
  *"is currently enabled"*) echo "Main is in maintenance mode: cutover copy" ;;
  *"is currently disabled"*)
    if [ "${ALLOW_LIVE_MAIN:-}" != 1 ]; then
      echo "Refusing: Main is NOT in maintenance mode (\"$mode\")." >&2
      echo "Cutover: run 'occ maintenance:mode --on' on Main first. Test copy: ALLOW_LIVE_MAIN=1." >&2
      exit 1
    fi
    cat >&2 <<'WARN'
################################################################################
WARNING: ALLOW_LIVE_MAIN=1 - Main is live. This is a TEST copy: everything
written on Main after the snapshot is NOT in prod's database. Never cut over
from this copy.
################################################################################
WARN
    ;;
  *)
    echo "Cannot read Main's maintenance mode: \"$mode\"" >&2
    exit 1
    ;;
esac

# A failed or truncated transfer never stays on prod.
cleanup() { ssh_ "$PROD" "sudo rm -f $part" </dev/null || true; }
trap cleanup EXIT

echo "prod: starting nextcloud-db, stopping nextcloud-app"
ssh_ "$PROD" bash -s <<'EOF_PROD'
set -euo pipefail
# The script arrives on stdin: no `docker exec -i` here.
sql() { sudo docker exec nextcloud-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$@"' sh "$@"; }
sudo systemctl stop docker-nextcloud-app.service
sudo systemctl start docker-nextcloud-db.service
for _ in $(seq 90); do
  sql mariadb-admin -u root ping >/dev/null 2>&1 && exit 0
  sleep 2
done
echo "nextcloud-db not ready" >&2
exit 1
EOF_PROD

echo "Main -> prod: dumping"
# --skip-routines: Main's mysql.proc still has a pre-10.7 layout (mariadb-upgrade never
# ran there; error 1728 "Cannot load from mysql.proc"), so dumping routines fails.
# Nextcloud has no stored routines (or events); triggers (none today) still come along.
# shellcheck disable=SC2016 # expanded inside Main's container
ssh_ "$MAIN" 'set -o pipefail; docker exec nextcloud-db sh -c '\''MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb-dump -u root --single-transaction --skip-routines --triggers nextcloud'\'' | gzip -c' </dev/null |
  ssh_ "$PROD" "sudo sh -c 'umask 077 && cat >$part'"

echo "prod: checking the dump, replacing the database"
ssh_ "$PROD" bash -s <<'EOF_PROD'
set -euo pipefail
dump=/var/lib/prod/nextcloud/sync-dump.sql.gz.part
marker=/var/lib/prod/nextcloud/SYNC-FAILED
trap 'sudo rm -f "$dump"' EXIT
# The script itself arrives on stdin: only the import gets `docker exec -i`.
sql() { sudo docker exec nextcloud-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$@"' sh "$@"; }
sql_in() { sudo docker exec -i nextcloud-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$@"' sh "$@"; }
sudo gzip -t "$dump"
sudo gzip -dc "$dump" | tail -n 1 | grep -q '^-- Dump completed' || {
  echo "dump incomplete" >&2
  exit 1
}
echo "dump: $(sudo du -h "$dump" | cut -f1) gzipped"
# From here on the database is incomplete until the import finishes.
sudo touch "$marker"
sql mariadb -u root -e 'DROP DATABASE IF EXISTS nextcloud;
  CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
  GRANT ALL PRIVILEGES ON nextcloud.* TO `nextcloud`@`%`;'
sudo gzip -dc "$dump" | sql_in mariadb -u root nextcloud
sudo rm -f "$dump" "$marker"
echo "tables: $(sql mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'nextcloud'")"
# Skipped (ConditionPathExists) until config/config.php is in place.
sudo systemctl start docker-nextcloud-app.service
EOF_PROD

echo "done"
