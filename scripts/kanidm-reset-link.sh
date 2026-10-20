#!/usr/bin/env bash
# Print a Kanidm credential reset (enrolment) link for one person, on Kanidm's own
# domain: https://id.vanwaaij.com/ui/reset?token=… (with --test the test Kanidm on VM
# 230, https://id-test.vanwaaij.com/…). Give it to the person; they open it and set up
# a passkey (or password + TOTP).
#
# Use this, not `kanidm person credential create-reset-token` from a CLI pointed at
# the VM's IP: the CLI builds the link from the address it talks to
# (https://10.0.10.111:8443/…), where a passkey can't be registered for the domain.
# On the identity VM, `kanidm-reset-link` (installed by modules/identity/kanidm.nix)
# recovers idm_admin inside the container, creates the token with the tools image and
# prints the link for the configured domain; the expiry goes to stderr.
#
# Runs from atlas (SSH to pve and the VM). A new link doesn't revoke an older one.
#
# Usage: scripts/kanidm-reset-link.sh <person> [--test] [--ttl <seconds>]
#   default ttl 86400 (a day). TARGET, JUMP override the SSH target and jump host.
set -euo pipefail

usage() {
  echo "usage: $0 <person> [--test] [--ttl <seconds>]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
person=$1
shift
[[ $person =~ ^[a-z0-9][a-z0-9_.-]*$ ]] || {
  echo "not a person name: $person" >&2
  exit 2
}
target_default=identity@10.0.10.111
ttl=86400
while [ "$#" -gt 0 ]; do
  case $1 in
  --test) target_default=router@10.0.10.230 ;;
  --ttl)
    [ "$#" -ge 2 ] && [[ $2 =~ ^[0-9]+$ ]] || usage
    ttl=$2
    shift
    ;;
  *) usage ;;
  esac
  shift
done

TARGET=${TARGET:-$target_default}
JUMP=${JUMP:-pve}

ssh -o BatchMode=yes -o ConnectTimeout=15 -J "$JUMP" "$TARGET" \
  "sudo kanidm-reset-link $person $ttl" </dev/null
