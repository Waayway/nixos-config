# Daily log budget per machine, enforced through Loki's runtime config (run by the
# loki-budget timer on the monitor VM, see loki.nix).
#
#   env: PROM_URL   Prometheus base URL
#        BUDGETS    JSON { "<tenant>": <MB per day> }
#        RUNTIME_FILE  Loki runtime config to write
#        TEXTFILE   node_exporter textfile to write
#
# A tenant that received more than its budget in the last 24h gets a near-zero rate
# limit (Loki then rejects every push) until the 24h window drops below budget again.
# If the query fails or returns nothing, the script exits non-zero and leaves both
# files as they are: a blip must neither lift a block nor block everyone.
set -euo pipefail

query='sum by (tenant) (increase(loki_distributor_bytes_received_total[24h]))'
resp=$(curl -fsS --max-time 30 --data-urlencode "query=$query" "$PROM_URL/api/v1/query")

if ! jq -e '.status == "success" and (.data.result | length) > 0' >/dev/null <<<"$resp"; then
  echo "loki-budget: Prometheus returned no usable result, keeping current limits" >&2
  exit 1
fi

# One line per budgeted tenant: "<tenant> <0|1>".
verdicts=$(jq -r --argjson budgets "$BUDGETS" '
  (.data.result | map({key: .metric.tenant, value: (.value[1] | tonumber)}) | from_entries) as $used
  | $budgets | to_entries[]
  | "\(.key) \(if ($used[.key] // 0) > (.value * 1048576) then 1 else 0 end)"
' <<<"$resp")

dir=$(dirname "$RUNTIME_FILE")
runtime_tmp=$(mktemp "$dir/.runtime.XXXXXX")
textfile_tmp=$(mktemp "$(dirname "$TEXTFILE")/.loki-budget.XXXXXX")
trap 'rm -f "$runtime_tmp" "$textfile_tmp"' EXIT

{
  echo "# HELP loki_budget_exceeded 1 while the tenant is over its daily log budget."
  echo "# TYPE loki_budget_exceeded gauge"
  while read -r tenant over; do
    echo "loki_budget_exceeded{tenant=\"$tenant\"} $over"
  done <<<"$verdicts"
} >"$textfile_tmp"

blocked=$(awk '$2 == 1 { print $1 }' <<<"$verdicts")
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
