# TrueNAS pool health as a node_exporter textfile metric (run by the truenas-pools timer
# on the monitor VM, see exporters.nix).
#
#   env: TRUENAS_HOST, TRUENAS_USER, TRUENAS_KEY, TRUENAS_KNOWN_HOSTS  SSH access, as
#                      for truenas-reconcile
#        TEXTFILE      textfile to write
#
# Reads `sudo midclt call pool.query` over SSH and writes
# `truenas_pool_healthy{pool="<name>"} 0|1` per pool (healthy: the pool's `healthy`
# field, else status ONLINE). If SSH or the parsing fails, the script exits non-zero
# and leaves the textfile as it is: a blip must not turn into "no data" or "unhealthy".
set -euo pipefail

out=$(ssh -n -i "$TRUENAS_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 \
  -o UserKnownHostsFile="$TRUENAS_KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
  "$TRUENAS_USER@$TRUENAS_HOST" "sudo midclt call pool.query") || {
  echo "truenas-pools: ssh to $TRUENAS_HOST failed, keeping the textfile" >&2
  exit 1
}

lines=$(jq -er '
  if type != "array" then error("not an array") else . end
  | if length == 0 then error("no pools") else . end
  | .[]
  | "truenas_pool_healthy{pool=\"\(.name | gsub("\\\\"; "\\\\") | gsub("\""; "\\\""))\"} \(if (if .healthy == null then .status == "ONLINE" else .healthy end) then 1 else 0 end)"
' <<<"$out") || {
  echo "truenas-pools: cannot parse pool.query output, keeping the textfile" >&2
  exit 1
}

tmp=$(mktemp "$(dirname "$TEXTFILE")/.truenas-pools.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
  echo "# HELP truenas_pool_healthy 1 if the pool reports healthy, else 0."
  echo "# TYPE truenas_pool_healthy gauge"
  echo "$lines"
} >"$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$TEXTFILE"
