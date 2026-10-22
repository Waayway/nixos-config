#!/usr/bin/env bash
# Copy one Kanidm OAuth2 client's secret into 1Password, where its consumer reads it
# with opnix: Homelab item `kanidm-oauth2-<client>` (field `credential`; with --test
# `kanidm-oauth2-<client>-test`, from the test Kanidm on VM 230).
#
# Kanidm generates the secret when kanidm-provision creates the client (the official
# image can't take a provisioned one, modules/server/identity/kanidm.nix). On the identity
# VM, `kanidm-oauth2-basic-secret` (installed by that module) recovers idm_admin inside
# the container and prints the secret with the tools image's
# `kanidm system oauth2 show-basic-secret`; it travels SSH stdout -> a shell variable
# -> 1Password (an item template on a pipe). It is never printed, never in argv,
# never on disk.
#
# Runs from atlas (SSH to pve and the VM, `op` signed in; 1Password asks for Touch
# ID). Rerun after the client is recreated or its secret reset: the item is updated.
#
# Usage: scripts/kanidm-oauth2-secret.sh <client> [--test]
#   TARGET, JUMP override the SSH target and jump host (defaults below).
set -euo pipefail

usage() {
  echo "usage: $0 <client> [--test]" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
client=$1
[[ $client =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
  echo "not a client name: $client" >&2
  exit 2
}
suffix=""
target_default=identity@10.0.10.111
if [ "$#" -eq 2 ]; then
  [ "$2" = "--test" ] || usage
  suffix="-test"
  target_default=router@10.0.10.230
fi

TARGET=${TARGET:-$target_default}
JUMP=${JUMP:-pve}
ACCOUNT=KVKXJLIAFVBK5GYLWVS37CJCTE
VAULT=Homelab
item="kanidm-oauth2-${client}${suffix}"

ssh_() { ssh -o BatchMode=yes -o ConnectTimeout=15 -J "$JUMP" "$@"; }
op_() { op --account "$ACCOUNT" "$@"; }

echo "Reading the secret of OAuth2 client '$client' on $TARGET"
SECRET=$(ssh_ "$TARGET" "sudo kanidm-oauth2-basic-secret $client" </dev/null)
if [ -z "$SECRET" ] || [[ $SECRET == *[[:space:]]* ]]; then
  echo "no usable secret for '$client' (is it provisioned, with a basic secret?)" >&2
  exit 1
fi
export SECRET

if op_ item get "$item" --vault "$VAULT" --format json >/dev/null 2>&1; then
  echo "Updating 1Password item $item"
  current=$(op_ item get "$item" --vault "$VAULT" --format json)
  op_ item edit "$item" --vault "$VAULT" --template <(
    jq 'if any(.fields[]?; .id == "credential" or .label == "credential")
        then (.fields[] | select(.id == "credential" or .label == "credential") | .value) = env.SECRET
        else .fields += [{ id: "credential", label: "credential", type: "CONCEALED", value: env.SECRET }]
        end' <<<"$current"
  ) >/dev/null
else
  echo "Creating 1Password item $item"
  op_ item create --vault "$VAULT" --template <(
    jq -n --arg title "$item" '{
      title: $title,
      category: "API_CREDENTIAL",
      fields: [{ id: "credential", label: "credential", type: "CONCEALED", value: env.SECRET }]
    }'
  ) >/dev/null
fi
unset SECRET
echo "Done: op://$VAULT/$item/credential"
