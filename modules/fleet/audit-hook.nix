# Activation hook: appends one JSON line per system activation (including
# manual `nixos-rebuild`/`darwin-rebuild` runs and boots) to the audit file
# that fleet-agent serves at GET /activations.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.services.fleet-agent;
  stateDir = "/var/lib/fleet-agent";
  bin.jq = "${pkgs.jq}/bin/jq";

  hook = ''
    (
      export PATH=${pkgs.coreutils}/bin:$PATH
      fleet_dir=${stateDir}
      mkdir -p "$fleet_dir"

      store_path="$systemConfig"

      revision=""
      if [ -x "$systemConfig/sw/bin/nixos-version" ]; then
        revision="$("$systemConfig/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)"
      fi
      if [ -z "$revision" ] && [ -r "$systemConfig/darwin-version.json" ]; then
        revision="$(${bin.jq} -r '.configurationRevision // empty' "$systemConfig/darwin-version.json" 2>/dev/null || true)"
      fi
      [ -n "$revision" ] || revision=unknown

      generation=""
      link="$(readlink /nix/var/nix/profiles/system 2>/dev/null || true)"
      case "$link" in
        system-*-link)
          generation="''${link#system-}"
          generation="''${generation%-link}"
          ;;
      esac

      sudo_user=""
      if [ -f "$fleet_dir/apply-in-progress.json" ]; then
        apply_id="$(${bin.jq} -r '.apply_id // empty' "$fleet_dir/apply-in-progress.json" 2>/dev/null || true)"
        trigger="apply:$apply_id"
      elif [ ! -e /run/current-system ]; then
        trigger=boot
      else
        trigger=manual
        sudo_user="''${SUDO_USER:-}"
      fi

      ${bin.jq} -nc \
        --argjson time "$(date +%s)" \
        --arg store_path "$store_path" \
        --arg revision "$revision" \
        --arg generation "$generation" \
        --arg trigger "$trigger" \
        --arg sudo_user "$sudo_user" \
        '{
          time: $time,
          store_path: $store_path,
          revision: $revision,
          generation: (if $generation == "" then null else ($generation | tonumber) end),
          trigger: $trigger,
          sudo_user: (if $sudo_user == "" then null else $sudo_user end)
        }' >> "$fleet_dir/activations.jsonl"
    ) || true
  '';
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs hostPlatform.isLinux {
        system.activationScripts.fleetAudit = {
          deps = [ ];
          text = hook;
        };
      })
      (lib.optionalAttrs hostPlatform.isDarwin {
        system.activationScripts.postActivation.text = lib.mkAfter hook;
      })
    ]
  );
}
