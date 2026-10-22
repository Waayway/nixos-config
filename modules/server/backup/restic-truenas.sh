# Runs ON TrueNAS as root (sent by modules/server/backup/restic.nix, never stored there).
#
#   bash -c "$this" restic-truenas <restic> <repo> <sb-user> <sb-host> <sb-port>
#        <known-hosts line> <snapshot prefix> <max age h> <tag> <dataset|/path>…
#
# stdin: the repository password (one line). The Storage Box key arrives through
# the forwarded SSH agent ($SSH_AUTH_SOCK). Each dataset is backed up from its
# newest "<prefix>*" snapshot, bind-mounted at /run/restic-view/<dataset> in a
# private mount namespace, so restic sees the same paths every run and can skip
# unchanged files. Arguments starting with "/" are files backed up live; SQLite
# databases among them (*.db) are copied with `.backup` first.
set -euo pipefail

restic=$1 repo=$2 sb_user=$3 sb_host=$4 sb_port=$5 known_host=$6 prefix=$7 max_age_h=$8 tag=$9
shift 9

umask 077
IFS= read -r RESTIC_PASSWORD
export RESTIC_PASSWORD RESTIC_REPOSITORY=$repo RESTIC_CACHE_DIR=/root/.cache/restic-nix
# No terminal here: without this restic reports nothing until it's done. One
# status line a minute goes to the journal and the Healthchecks log.
export RESTIC_PROGRESS_FPS=0.016

view=/run/restic-view
work=$(mktemp -d /run/restic-nix.XXXXXX)
# Live copies (TrueNAS config database) don't outlive the run.
trap 'rm -rf "$work" "$view/live"' EXIT
printf '%s\n' "$known_host" >"$work/known_hosts"

now=$(date +%s)
binds=()
paths=()
for item in "$@"; do
  if [[ $item == /* ]]; then
    dest="$view/live$item"
    mkdir -p "$(dirname "$dest")"
    if [[ $item == *.db ]]; then
      sqlite3 "$item" ".backup '$dest'"
    else
      cp -a "$item" "$dest"
    fi
    paths+=("$dest")
    continue
  fi
  snapdir="/mnt/$item/.zfs/snapshot"
  snap=$(find "$snapdir" -mindepth 1 -maxdepth 1 -name "$prefix*" -printf '%f\n' | sort | tail -n 1)
  if [ -z "$snap" ]; then
    echo "no $prefix* snapshot of $item" >&2
    exit 1
  fi
  # <prefix>YYYY-mm-dd_HH-MM
  stamp=${snap#"$prefix"}
  taken=$(date -d "${stamp:0:10} ${stamp:11:2}:${stamp:14:2}" +%s)
  if [ $((now - taken)) -gt $((max_age_h * 3600)) ]; then
    echo "newest snapshot of $item is $snap, older than ${max_age_h}h" >&2
    exit 1
  fi
  echo "$item: $snap"
  ls "$snapdir/$snap" >/dev/null # trigger the snapshot automount
  mkdir -p "$view/$item"
  binds+=("$snapdir/$snap" "$view/$item")
  paths+=("$view/$item")
done

sftp_command="ssh -p $sb_port -o BatchMode=yes -o ServerAliveInterval=60 \
-o UserKnownHostsFile=$work/known_hosts -o StrictHostKeyChecking=yes $sb_user@$sb_host -s sftp"

# Bind the snapshots in a private mount namespace: nothing stays mounted after.
# The inner script takes its values as arguments, hence single quotes.
# shellcheck disable=SC2016
unshare --mount --propagation private -- bash -euo pipefail -c '
  restic=$1 sftp_command=$2 tag=$3 nbinds=$4
  shift 4
  while [ "$nbinds" -gt 0 ]; do
    mount --bind -o ro "$1" "$2"
    shift 2
    nbinds=$((nbinds - 2))
  done
  "$restic" -o sftp.command="$sftp_command" backup \
    --host truenas --tag nix --tag "$tag" \
    --compression auto --exclude-caches --read-concurrency 4 \
    "$@"
' restic-backup "$restic" "$sftp_command" "$tag" "${#binds[@]}" "${binds[@]}" "${paths[@]}"
