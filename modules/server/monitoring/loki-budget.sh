# Daily log budget per machine, enforced through Loki's runtime config (run by the
# loki-budget timer on the monitor VM, see loki.nix).
#
#   env: PROM_URL   Prometheus base URL
#        BUDGETS    JSON { "<tenant>": <MB per day> }
#        RUNTIME_FILE  Loki runtime config to write
#        TEXTFILE   node_exporter textfile to write
#
# The budget counts ACCEPTED bytes: received minus rate_limited discards over 24h.
# (loki_distributor_bytes_received_total is incremented before the rate-limit check, so
# a blocked host that keeps pushing would otherwise never drop back under budget.)
# A tenant over its budget gets a near-zero rate limit (Loki then rejects every push)
# until its accepted bytes in the 24h window fall below budget again.
# If the query fails, the script exits non-zero; if it returns no series at all ("no
# data yet", e.g. a fresh monitor) it exits 0. Either way both files stay as they are:
# a blip must neither lift a block nor block everyone.
set -euo pipefail

received='sum by (tenant) (increase(loki_distributor_bytes_received_total[24h]))'
discarded='sum by (tenant) (increase(loki_discarded_bytes_total{reason="rate_limited"}[24h]))'
# `or received * 0` gives tenants without a discard series a zero to subtract.
query="$received - on (tenant) ($discarded or $received * 0)"
resp=$(curl -fsS --max-time 30 --data-urlencode "query=$query" "$PROM_URL/api/v1/query")

if ! jq -e '.status == "success"' >/dev/null <<<"$resp"; then
  echo "loki-budget: Prometheus query failed, keeping current limits" >&2
  exit 1
fi
if [ "$(jq '.data.result | length' <<<"$resp")" = 0 ]; then
  echo "loki-budget: no data yet, keeping current limits" >&2
  exit 0
fi

# One line per budgeted tenant: "<tenant> <0|1>".
verdicts=$(jq -r --argjson budgets "$BUDGETS" '
  (.data.result | map({key: .metric.tenant, value: (.value[1] | tonumber)}) | from_entries) as $used
  | $budgets | to_entries[]
  | "\(.key) \(if ($used[.key] // 0) > (.value * 1048576) then 1 else 0 end)"
' <<<"$resp")

if [ "$(jq 'length' <<<"$BUDGETS")" = 0 ]; then
  verdicts=""
fi

dir=$(dirname "$RUNTIME_FILE")
runtime_tmp=$(mktemp "$dir/.runtime.XXXXXX")
textfile_tmp=$(mktemp "$(dirname "$TEXTFILE")/.loki-budget.XXXXXX")
trap 'rm -f "$runtime_tmp" "$textfile_tmp"' EXIT

{
  echo "# HELP loki_budget_exceeded 1 while the tenant is over its daily log budget."
  echo "# TYPE loki_budget_exceeded gauge"
  while read -r tenant over; do
    [ -n "$tenant" ] || continue
    echo "loki_budget_exceeded{tenant=\"$tenant\"} $over"
  done <<<"$verdicts"
} >"$textfile_tmp"

blocked=$(awk '$2 == 1 { print $1 }' <<<"$verdicts" || true)
if [ -z "$blocked" ]; then
  echo "overrides: {}" >"$runtime_tmp"
else
  {
    echo "overrides:"
    while read -r tenant; do
      echo "  $tenant:"
      echo "    ingestion_rate_mb: 0.0001"
      echo "    ingestion_burst_size_mb: 0.0001"
    done <<<"$blocked"
  } >"$runtime_tmp"
fi

chmod 0644 "$runtime_tmp" "$textfile_tmp"
mv "$runtime_tmp" "$RUNTIME_FILE"
mv "$textfile_tmp" "$TEXTFILE"
