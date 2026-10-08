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
        sudo -H --user=${user.name} -- /bin/sh -c '
          f="$HOME/Library/Application Support/VSCodium/User/settings.json"
          mkdir -p "$(dirname "$f")"
          [ -s "$f" ] || echo "{}" >"$f"
          if "$1" -e ".\"update.mode\" != \"none\"" "$f" >/dev/null; then
            tmp="$(mktemp)"
            "$1" ".\"update.mode\" = \"none\"" "$f" >"$tmp" && cat "$tmp" >"$f"
            rm -f "$tmp"
          fi
        ' sh ${pkgs.jq}/bin/jq || echo "could not set VSCodium update.mode (settings.json not plain JSON?)" >&2
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
