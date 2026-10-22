#!/usr/bin/env bash
# Shell test of modules/server/monitoring/loki-budget.sh with a fake curl on PATH.
# Runs anywhere with bash and jq: bash tests/loki-budget.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
script=$here/modules/server/monitoring/loki-budget.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

# Fake curl: FAKE_MODE picks the reply.
cat >"$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
case "$FAKE_MODE" in
  fail) exit 7 ;;
  error) echo '{"status":"error","errorType":"bad_data","error":"boom"}' ;;
  empty) echo '{"status":"success","data":{"resultType":"vector","result":[]}}' ;;
  over) echo '{"status":"success","data":{"resultType":"vector","result":[{"metric":{"tenant":"router"},"value":[1,"262144000"]},{"metric":{"tenant":"prod"},"value":[1,"1048576"]}]}}' ;;
  under) echo '{"status":"success","data":{"resultType":"vector","result":[{"metric":{"tenant":"router"},"value":[1,"1048576"]}]}}' ;;
esac
FAKE
chmod +x "$work/bin/curl"

export PATH="$work/bin:$PATH"
export PROM_URL=http://127.0.0.1:9090
export BUDGETS='{"router":200,"prod":200}'
export RUNTIME_FILE=$work/runtime.yaml
export TEXTFILE=$work/loki-budget.prom

fails=0
check() { # description, condition result
  if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$2" "$1" && echo ok || echo no; }

# 1. router over budget
FAKE_MODE=over bash "$script"
check "runtime has overrides" "$(has "$RUNTIME_FILE" 'overrides:')"
check "runtime blocks router" "$(has "$RUNTIME_FILE" 'router:')"
check "runtime rate" "$(has "$RUNTIME_FILE" 'ingestion_rate_mb: 0.0001')"
check "runtime burst" "$(has "$RUNTIME_FILE" 'ingestion_burst_size_mb: 0.0001')"
check "runtime does not block prod" "$([ "$(grep -c 'prod:' "$RUNTIME_FILE")" = 0 ] && echo ok || echo no)"
check "textfile router 1" "$(has "$TEXTFILE" 'loki_budget_exceeded{tenant="router"} 1')"
check "textfile prod 0" "$(has "$TEXTFILE" 'loki_budget_exceeded{tenant="prod"} 0')"

# 2. failures keep both files as they are
cp "$RUNTIME_FILE" "$work/runtime.before"
cp "$TEXTFILE" "$work/textfile.before"
for mode in fail error empty; do
  rc=0
  FAKE_MODE=$mode bash "$script" 2>/dev/null || rc=$?
  check "$mode exits non-zero" "$([ "$rc" != 0 ] && echo ok || echo no)"
  check "$mode keeps runtime file" "$(cmp -s "$RUNTIME_FILE" "$work/runtime.before" && echo ok || echo no)"
  check "$mode keeps textfile" "$(cmp -s "$TEXTFILE" "$work/textfile.before" && echo ok || echo no)"
done

# 3. everyone under budget lifts the block
FAKE_MODE=under bash "$script"
check "runtime empty overrides" "$(has "$RUNTIME_FILE" 'overrides: {}')"
check "textfile router 0" "$(has "$TEXTFILE" 'loki_budget_exceeded{tenant="router"} 0')"
check "textfile prod 0 (no data)" "$(has "$TEXTFILE" 'loki_budget_exceeded{tenant="prod"} 0')"
check "no 1 in textfile" "$(grep -q '} 1' "$TEXTFILE" && echo no || echo ok)"

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
