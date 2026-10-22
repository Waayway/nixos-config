# Make TrueNAS match the state declared in Nix (modules/server/truenas/truenas.nix).
#
#   truenas-reconcile [apply|check]
#
# Talks to the TrueNAS middleware with `sudo midclt call` over SSH. Per kind:
#   snapshotTasks  matched by dataset + naming schema; created/updated, never deleted
#   datasets       existing datasets only; listed properties updated
#   cronJobs       matched by description "[nix] <name>: …"; created/updated, and
#                  deleted when no longer declared
#   nfsShares      matched by comment "[nix] <name>"; same as cron jobs
# Anything without the "[nix] " marker that isn't declared is left alone.
# Environment: TRUENAS_HOST, TRUENAS_USER, TRUENAS_KEY, TRUENAS_KNOWN_HOSTS, DESIRED (JSON file).


mode=${1:-apply}
case $mode in apply | check) ;; *)
  echo "usage: truenas-reconcile [apply|check]" >&2
  exit 2
  ;;
esac

changes=0

# -n: midclt never needs stdin, and ssh would otherwise eat the input of the
# `while read` loops below.
tn() {
  ssh -n -i "$TRUENAS_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 \
    -o UserKnownHostsFile="$TRUENAS_KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
    "$TRUENAS_USER@$TRUENAS_HOST" "$@"
}

# call <method> [json args…]: one middleware call, JSON result on stdout.
call() {
  local quoted
  quoted=$(printf '%q ' "$@")
  tn "sudo midclt call $quoted"
}

# Is every key of $want present in $have with the same value (recursively)?
subset='def sub($h; $w):
  if ($w | type) == "object" then
    ($h | type) == "object" and all($w | keys[]; . as $k | sub($h[$k]; $w[$k]))
  else $h == $w end;'

report() { printf '%s %-14s %s\n' "$1" "$2" "$3"; }

# act <symbol> <kind> <label> <method> [args…]: run (apply) or only report (check).
act() {
  local sym=$1 kind=$2 label=$3
  shift 3
  changes=$((changes + 1))
  if [ "$mode" = apply ]; then
    call "$@" >/dev/null
    report "$sym" "$kind" "$label"
  else
    report "$sym" "$kind" "$label (would change)"
  fi
}

# --- snapshot tasks -----------------------------------------------------------
current=$(call pool.snapshottask.query)
while IFS= read -r want; do
  ds=$(jq -r .dataset <<<"$want")
  ns=$(jq -r .naming_schema <<<"$want")
  have=$(jq -c --arg ds "$ds" --arg ns "$ns" \
    'map(select(.dataset == $ds and .naming_schema == $ns)) | first // empty' <<<"$current")
  if [ -z "$have" ]; then
    act + snapshot-task "$ds ($ns)" pool.snapshottask.create "$want"
  elif jq -e --argjson w "$want" "$subset sub(.; \$w)" <<<"$have" >/dev/null; then
    report "=" snapshot-task "$ds ($ns)"
  else
    act '~' snapshot-task "$ds ($ns)" pool.snapshottask.update "$(jq .id <<<"$have")" "$want"
  fi
done < <(jq -c '.snapshotTasks[]' "$DESIRED")
jq -r --slurpfile d "$DESIRED" \
  '.[] | select([.dataset, .naming_schema] as $k | $d[0].snapshotTasks | map([.dataset, .naming_schema]) | index([$k]) | not)
       | "? snapshot-task  \(.dataset) (\(.naming_schema)) not declared, left alone"' <<<"$current"

# --- dataset properties ---------------------------------------------------------
while IFS= read -r want; do
  id=$(jq -r .id <<<"$want")
  have=$(call pool.dataset.query "$(jq -nc --arg id "$id" '[["id", "=", $id]]')" | jq -c 'first // empty')
  if [ -z "$have" ]; then
    echo "! dataset        $id does not exist (datasets are not created here)" >&2
    exit 1
  fi
  # Declared properties without a value (null) are not managed.
  props=$(jq -c '.props | with_entries(select(.value != null))' <<<"$want")
  # The middleware returns properties as { value, rawvalue, source, … }.
  if jq -e --argjson p "$props" '. as $h | all($p | to_entries[];
       (($h[.key].value // "") | ascii_upcase) == (.value | ascii_upcase))' <<<"$have" >/dev/null; then
    report "=" dataset "$id"
  else
    act '~' dataset "$id $props" pool.dataset.update "$id" "$props"
  fi
done < <(jq -c '.datasets[]' "$DESIRED")

# --- marker-matched kinds (cron jobs, NFS shares) -------------------------------
# reconcile_marked <kind> <query> <create> <update> <delete> <marker field> <desired key>
reconcile_marked() {
  local kind=$1 query=$2 create=$3 update=$4 delete=$5 field=$6 key=$7 current want name marker have
  current=$(call "$query")
  while IFS= read -r want; do
    name=$(jq -r .name <<<"$want")
    marker="[nix] $name"
    want=$(jq -c .spec <<<"$want")
    have=$(jq -c --arg f "$field" --arg m "$marker" \
      'map(select((.[$f] // "") == $m or ((.[$f] // "") | startswith($m + ":")))) | first // empty' <<<"$current")
    if [ -z "$have" ]; then
      act + "$kind" "$name" "$create" "$want"
    elif jq -e --argjson w "$want" "$subset sub(.; \$w)" <<<"$have" >/dev/null; then
      report "=" "$kind" "$name"
    else
      act '~' "$kind" "$name" "$update" "$(jq .id <<<"$have")" "$want"
    fi
  done < <(jq -c --arg k "$key" '.[$k][]' "$DESIRED")
  # Delete what carries the marker but is no longer declared.
  while IFS=$'\t' read -r id label; do
    act - "$kind" "$label" "$delete" "$id"
  done < <(jq -r --arg f "$field" --arg k "$key" --slurpfile d "$DESIRED" '
      ($d[0][$k] | map("[nix] " + .name)) as $declared
      | .[] | (.[$f] // "") as $m
      | select($m | startswith("[nix] "))
      | select(($m | split(":")[0]) as $base | $declared | index($base) | not)
      | "\(.id)\t\($m)"' <<<"$current")
}

reconcile_marked cron-job cronjob.query cronjob.create cronjob.update cronjob.delete description cronJobs
reconcile_marked nfs-share sharing.nfs.query sharing.nfs.create sharing.nfs.update sharing.nfs.delete comment nfsShares

if [ "$mode" = check ] && [ "$changes" -gt 0 ]; then
  echo "$changes change(s) pending" >&2
  exit 1
fi
echo "done: $changes change(s)"
