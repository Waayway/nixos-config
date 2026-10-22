#!/usr/bin/env bash
# Shell test of modules/server/monitoring/healthchecks-sync.sh with a fake curl on PATH.
# Runs anywhere with bash and jq: bash tests/healthchecks-sync.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
script=$here/modules/server/monitoring/healthchecks-sync.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

# Fake curl: logs the URL, the header file's content and the body (stdin); answers with
# the next status code from $FAKE_CODES (space separated), 201 when it runs out.
cat >"$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
out=/dev/null
url=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -H) case "$2" in @*) cat "${2#@}" >>"$FAKE_DIR/headers" ;; esac; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
echo "$url" >>"$FAKE_DIR/urls"
cat >>"$FAKE_DIR/bodies"
echo >>"$FAKE_DIR/bodies"
n=$(($(cat "$FAKE_DIR/n" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FAKE_DIR/n"
code=$(echo "${FAKE_CODES:-}" | awk -v n="$n" '{print $n}')
echo '{}' >"$out"
echo "${code:-201}"
FAKE
chmod +x "$work/bin/curl"

export PATH="$work/bin:$PATH"
export FAKE_DIR=$work
echo 'secret-api-key' >"$work/key"
export HC_API_KEY_FILE=$work/key
export CHECKS='[
  {"slug":"homelab-host-down","name":"Host down","timeout":31536000,"grace":60,"filter":true},
  {"slug":"homelab-watchdog","name":"Watchdog","timeout":300,"grace":300,"filter":false}
]'

fails=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
body() { sed -n "${1}p" "$work/bodies"; }
yes() { if "$@" >/dev/null 2>&1; then echo ok; else echo no; fi; }
reset() { rm -f "$work"/{urls,bodies,headers,n}; }

reset
FAKE_CODES="201 200" bash "$script" 2>"$work/err"
check "two POSTs" "$(yes test "$(wc -l <"$work/urls")" -eq 2)"
check "api url" "$(yes test "$(sort -u "$work/urls")" = "https://healthchecks.io/api/v3/checks/")"
check "api key in a header file" "$(yes grep -qx 'X-Api-Key: secret-api-key' "$work/headers")"
a=$(body 1)
w=$(body 3)
check "alert: slug" "$(yes jq -e '.slug == "homelab-host-down"' <<<"$a")"
check "alert: unique slug" "$(yes jq -e '.unique == ["slug"]' <<<"$a")"
check "alert: tags" "$(yes jq -e '.tags == "homelab monitoring"' <<<"$a")"
check "alert: channels" "$(yes jq -e '.channels == "*"' <<<"$a")"
check "alert: timeout 365 days" "$(yes jq -e '.timeout == 31536000' <<<"$a")"
check "alert: filter_http_body" "$(yes jq -e '.filter_http_body == true' <<<"$a")"
check "alert: failure_kw" "$(yes jq -e '.failure_kw == "\"status\":\"firing\""' <<<"$a")"
check "alert: success_kw" "$(yes jq -e '.success_kw == "\"status\":\"resolved\""' <<<"$a")"
check "alert: ignore unmatched" "$(yes jq -e '.filter_default_fail == false' <<<"$a")"
check "watchdog: timeout 300" "$(yes jq -e '.timeout == 300 and .grace == 300' <<<"$w")"
check "watchdog: no failure_kw" "$(yes jq -e 'has("failure_kw") | not' <<<"$w")"
check "watchdog: no filter_http_body" "$(yes jq -e '(.filter_http_body // false) == false' <<<"$w")"

reset
rc=0
FAKE_CODES="201 403" bash "$script" 2>"$work/err" || rc=$?
check "403 on the second: non-zero exit" "$(yes test "$rc" -ne 0)"
check "403: stderr names homelab-watchdog" "$(yes grep -q homelab-watchdog "$work/err")"
check "403: stderr has the status" "$(yes grep -q 403 "$work/err")"

reset
rc=0
FAKE_CODES="500" bash "$script" 2>"$work/err" || rc=$?
check "500 on the first: non-zero exit" "$(yes test "$rc" -ne 0)"
check "500: stderr names homelab-host-down" "$(yes grep -q homelab-host-down "$work/err")"
check "stops after the first failure" "$(yes test "$(wc -l <"$work/urls")" -eq 1)"

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
