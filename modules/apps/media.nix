args@{
  pkgs,
  inputs,
  user,
  tools,
  ...
}:
let
  # TidaLuna (TIDAL client mod): the app's resources/app.asar is renamed to
  # original.asar and Luna's files go in resources/app/.
  luna = inputs.tidaluna;
in
tools.mkAppCategory args {
  name = "media";
  apps = {
    spotify = {
      linux = [ pkgs.spotify ];
      darwinCasks = [ "spotify" ];
    };
    spot.linux = [ pkgs.spot ];
    sone.linux = [ pkgs.sone ];
    tidal = {
      linux = [
        (pkgs.tidal-hifi.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            r=$out/share/tidal-hifi/resources
            mv $r/app.asar $r/original.asar
            cp -R ${luna} $r/app
          '';
        }))
      ];
      darwinCasks = [ "tidal" ];
      # The cask's TIDAL.app updates itself, so inject into it in place (after
      # Homebrew) instead of packaging the app. A TIDAL self-update drops the
      # mod again until the next switch. The marker file holds the injected
      # store path, so an unchanged install isn't touched or re-signed.
      # Writing into another app's bundle needs the App Management permission
      # for the terminal running darwin-rebuild; without it the first copy
      # fails and the app is left as it was.
      darwinConfig.system.activationScripts.postActivation.text = ''
        sudo -H --user=${user.name} -- /bin/sh -c '
          set -e
          r=/Applications/TIDAL.app/Contents/Resources
          [ -d "$r" ] || exit 0
          [ "$(cat "$r/app/.nix-luna" 2>/dev/null)" = "$1" ] && [ ! -e "$r/app.asar" ] && exit 0
          echo "injecting TidaLuna into TIDAL.app" >&2
          # Copies from the store are read-only, so make old ones removable.
          for d in "$r/app.new" "$r/app"; do
            [ ! -e "$d" ] || chmod -R u+w "$d"
          done
          rm -rf "$r/app.new"
          cp -R "$1" "$r/app.new"
          chmod -R u+w "$r/app.new"
          echo "$1" >"$r/app.new/.nix-luna"
          rm -rf "$r/app"
          mv "$r/app.new" "$r/app"
          [ ! -e "$r/app.asar" ] || mv -f "$r/app.asar" "$r/original.asar"
          codesign --force --deep --sign - /Applications/TIDAL.app
        ' sh ${luna} || echo "could not inject TidaLuna into TIDAL.app (App Management permission?)" >&2
      '';
    };
    obs = {
      linux = [ pkgs.obs-studio ];
      darwinCasks = [ "obs" ];
    };
    audacity = {
      linux = [ pkgs.audacity ];
      darwinCasks = [ "audacity" ]; # aarch64-darwin nixpkgs build is unreliable
    };
    krita = {
      linux = [ pkgs.krita ];
      darwinCasks = [ "krita" ];
    };
    gimp.linux = [ pkgs.gimp ];
    inkscape.linux = [ pkgs.inkscape ];
    figma.linux = [ pkgs.figma-linux ];
    mpv.linux = [ pkgs.mpv ];
    qbittorrent.linux = [ pkgs.qbittorrent ];
    popsicle.linux = [ pkgs.popsicle ]; # ISO flasher
  };
}
