#!/usr/bin/env bash
# Copy old Main's Nextcloud database into VM 100's (prod) nextcloud-db: a fresh dump
# from Main, then drop, recreate and import on prod. Used for the test copy (Task 5)
# and again at the cutover (Task 8).
#
# Runs from atlas (or any machine with SSH to pve and both VMs; prod has no key for
# Main): the dump streams Main -> here -> prod. Main is only read
# (`--single-transaction`, a consistent snapshot; its app keeps running). Passwords
# stay inside the containers (MYSQL_PWD from their own environment), never in argv.
#
# On prod the app is stopped while the database is replaced and started again
# afterwards (it only starts once config/config.php exists). The dump lands in a
# root-only file on prod first, so a broken transfer never touches the database.
#
# Usage: scripts/prod-sync-nextcloud-db.sh
#   MAIN, PROD, JUMP override the SSH targets (defaults below).
set -euo pipefail

MAIN=${MAIN:-goedenaam@10.0.10.108}
PROD=${PROD:-prod@10.0.10.100}
JUMP=${JUMP:-pve}

ssh_() { ssh -o BatchMode=yes -o ConnectTimeout=15 -J "$JUMP" "$@"; }

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
# shellcheck disable=SC2016 # expanded inside Main's container
ssh_ "$MAIN" 'docker exec nextcloud-db sh -c '\''MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb-dump -u root --single-transaction --routines --triggers nextcloud'\'' | gzip -c' </dev/null |
  ssh_ "$PROD" 'sudo sh -c "umask 077 && cat >/var/lib/prod/nextcloud/sync-dump.sql.gz.tmp" &&
    sudo mv /var/lib/prod/nextcloud/sync-dump.sql.gz.tmp /var/lib/prod/nextcloud/sync-dump.sql.gz'

echo "prod: checking the dump, replacing the database"
ssh_ "$PROD" bash -s <<'EOF_PROD'
set -euo pipefail
dump=/var/lib/prod/nextcloud/sync-dump.sql.gz
# The script itself arrives on stdin: only the import gets `docker exec -i`.
sql() { sudo docker exec nextcloud-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$@"' sh "$@"; }
sql_in() { sudo docker exec -i nextcloud-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$@"' sh "$@"; }
sudo gzip -t "$dump"
sudo gzip -dc "$dump" | tail -n 1 | grep -q '^-- Dump completed' || {
  echo "dump incomplete" >&2
  exit 1
}
echo "dump: $(sudo du -h "$dump" | cut -f1) gzipped"
sql mariadb -u root -e 'DROP DATABASE IF EXISTS nextcloud;
  CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
  GRANT ALL PRIVILEGES ON nextcloud.* TO `nextcloud`@`%`;'
sudo gzip -dc "$dump" | sql_in mariadb -u root nextcloud
sudo rm -f "$dump"
echo "tables: $(sql mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'nextcloud'")"
# Skipped (ConditionPathExists) until config/config.php is in place.
sudo systemctl start docker-nextcloud-app.service
EOF_PROD

echo "done"
