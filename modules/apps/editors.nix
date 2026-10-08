args@{ pkgs, user, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "editors";
  apps = {
    vscodium = {
      linux = [ pkgs.vscodium ];
      darwinPkgs = [ pkgs.vscodium ];
      # The app lives in the read-only nix store, so its self-updater keeps
      # asking to install a privileged helper and fails. Updates come from
      # nix; switch the updater off without taking over settings.json.
      darwinConfig.system.activationScripts.postActivation.text = ''
        f=~${user.name}/Library/"Application Support"/VSCodium/User/settings.json
        sudo --user=${user.name} -- mkdir -p "$(dirname "$f")"
        [ -s "$f" ] || echo '{}' | sudo --user=${user.name} -- tee "$f" >/dev/null
        if ${pkgs.jq}/bin/jq -e '."update.mode" != "none"' "$f" >/dev/null 2>&1; then
          tmp="$(mktemp)"
          ${pkgs.jq}/bin/jq '."update.mode" = "none"' "$f" >"$tmp" \
            && sudo --user=${user.name} -- cp "$tmp" "$f"
          rm -f "$tmp"
        fi
      '';
    };
    zed.darwinCasks = [ "zed" ];
    cursor.darwinCasks = [ "cursor" ];
    android-studio = {
      linux = [ pkgs.android-studio ];
      darwinCasks = [ "android-studio" ];
    };
  };
}
