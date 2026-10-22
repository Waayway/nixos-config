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
# non-zero. After a 200/201 the response's check object must echo `filter_http_body` and
# `failure_kw` for filtered checks; if not, the script exits non-zero naming the slug.
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
    200 | 201)
      # The check object in the response must echo the filter settings, otherwise the
      # check would treat every webhook as a plain ping (e.g. a resolved alert as up).
      if jq -e . "$work/response" >/dev/null 2>&1 && jq -e --argjson sent "$body" '
        if $sent.filter_http_body then
          .filter_http_body == true and .failure_kw == $sent.failure_kw
        else true end
      ' "$work/response" >/dev/null 2>&1; then
        echo "healthchecks-sync: $slug ($code)"
      else
        echo "healthchecks-sync: $slug: response does not echo filter_http_body/failure_kw: $(head -c 300 "$work/response")" >&2
        exit 1
      fi
      ;;
    *)
      echo "healthchecks-sync: $slug failed with status $code: $(head -c 300 "$work/response" 2>/dev/null)" >&2
      exit 1
      ;;
  esac
done
