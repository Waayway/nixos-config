#!/usr/bin/env bash
# Shell test of modules/server/monitoring/truenas-pools.sh with a fake ssh on PATH.
# Runs anywhere with bash and jq: bash tests/truenas-pools.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
script=$here/modules/server/monitoring/truenas-pools.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

cat >"$work/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_ARGS"
case "$FAKE_MODE" in
  fail) exit 255 ;;
  garbage) echo 'not json' ;;
  healthy) echo '[{"name":"store","healthy":true,"status":"ONLINE"},{"name":"archive","healthy":true,"status":"ONLINE"}]' ;;
  degraded) echo '[{"name":"store","healthy":false,"status":"DEGRADED"},{"name":"archive","healthy":true,"status":"ONLINE"}]' ;;
  flagwins) echo '[{"name":"store","healthy":false,"status":"ONLINE"}]' ;;
  nohealthy) echo '[{"name":"store","status":"ONLINE"},{"name":"bad","status":"FAULTED"}]' ;;
esac
FAKE
chmod +x "$work/bin/ssh"

export PATH="$work/bin:$PATH"
export FAKE_ARGS=$work/ssh-args
export TRUENAS_HOST=10.0.10.130 TRUENAS_USER=automation TRUENAS_KEY=/k TRUENAS_KNOWN_HOSTS=/kh
export TEXTFILE=$work/truenas-pools.prom

fails=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
has() { grep -qF -- "$2" "$1" && echo ok || echo no; }

FAKE_MODE=healthy bash "$script"
check "store healthy" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="store"} 1')"
check "archive healthy" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="archive"} 1')"
check "calls midclt pool.query via sudo" "$(has "$FAKE_ARGS" 'sudo midclt call pool.query')"
check "ssh as automation@host" "$(has "$FAKE_ARGS" 'automation@10.0.10.130')"
check "strict host key checking" "$(has "$FAKE_ARGS" 'StrictHostKeyChecking=yes')"

FAKE_MODE=degraded bash "$script"
check "degraded store is 0" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="store"} 0')"
check "archive still 1" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="archive"} 1')"

FAKE_MODE=nohealthy bash "$script"
check "status ONLINE counts as healthy" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="store"} 1')"
check "status FAULTED is 0" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="bad"} 0')"

FAKE_MODE=flagwins bash "$script"
check "healthy=false wins over status ONLINE" "$(has "$TEXTFILE" 'truenas_pool_healthy{pool="store"} 0')"

cp "$TEXTFILE" "$work/before"
for mode in fail garbage; do
  rc=0
  FAKE_MODE=$mode bash "$script" 2>/dev/null || rc=$?
  check "$mode exits non-zero" "$([ "$rc" != 0 ] && echo ok || echo no)"
  check "$mode keeps textfile" "$(cmp -s "$TEXTFILE" "$work/before" && echo ok || echo no)"
done
check "no temp files left" "$([ "$(ls -A "$work" | grep -c '^\.truenas-pools')" = 0 ] && echo ok || echo no)"

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
