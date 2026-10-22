# Creates or updates the Healthchecks.io checks of the homelab alerts (run by the
# healthchecks-sync oneshot on the monitor VM, see alerts.nix).
#
#   env: HC_API_KEY_FILE  file with the project's read-write API key
#        CHECKS           JSON list of { slug, name, timeout, grace, filter }
#
# One `POST /api/v3/checks/` per check with `unique: ["slug"]`: 201 = created, 200 =
# updated. A check with `filter` only reacts to Grafana's webhook body (failure keyword
# firing, success keyword resolved, anything else ignored). On any other status (403:
# the free plan's 20-check limit) the script stops at once, names the slug and exits
# non-zero.
set -euo pipefail

url=https://healthchecks.io/api/v3/checks/
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077
# The key goes through a header file, not the command line.
printf 'X-Api-Key: %s\n' "$(tr -d '[:space:]' <"$HC_API_KEY_FILE")" >"$work/headers"

jq -c '.[]' <<<"$CHECKS" | while read -r check; do
  slug=$(jq -r .slug <<<"$check")
  body=$(jq -c '
    {
      name, slug, timeout, grace,
      tags: "homelab monitoring",
      channels: "*",
      unique: ["slug"]
    }
    + (if .filter then {
        filter_http_body: true,
        failure_kw: "\"status\":\"firing\"",
        success_kw: "\"status\":\"resolved\"",
        filter_default_fail: false
      } else {} end)
  ' <<<"$check")
  code=$(curl -sS -o "$work/response" -w '%{http_code}' -X POST \
    -H "@$work/headers" -H 'Content-Type: application/json' \
    --data-binary @- "$url" <<<"$body") || code=curl-failed
  case "$code" in
    200 | 201) echo "healthchecks-sync: $slug ($code)" ;;
    *)
      echo "healthchecks-sync: $slug failed with status $code: $(head -c 300 "$work/response" 2>/dev/null)" >&2
      exit 1
      ;;
  esac
done
