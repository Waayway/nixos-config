args@{
  pkgs,
  tools,
  ...
}:
tools.mkAppCategory args {
  name = "media";
  apps = {
    spotify = {
      linux = [ pkgs.spotify ];
      darwinCasks = [ "spotify" ];
    };
    oxitide = {
      flatpak = [
        {
          flatpakref = "https://flatpak.oxitide.com/oxitide.flatpakref";
          sha256 = "1yhpqlriisy0dvgg53sxmyfsxmvbypf1fz2rpgp0dvhn18fr0346";
        }
      ];
      # No cask; the universal release zip, copied to /Applications/Nix Apps.
      darwinPkgs = [
        (pkgs.stdenvNoCC.mkDerivation rec {
          pname = "oxitide";
          version = "0.2.2";
          src = pkgs.fetchurl {
            url = "https://github.com/yelanxin/OxiTide/releases/download/v${version}/OxiTide-${version}-macos-universal.zip";
            hash = "sha256-p2UcI+hE6GRL9CtgnK4cQzp3307uG4ZUdpK418smuCs=";
          };
          nativeBuildInputs = [ pkgs.unzip ];
          sourceRoot = ".";
          # The zip ships a Finder custom-icon file (Icon) in the bundle root, which
          # breaks the (ad-hoc) code signature check.
          installPhase = ''
            rm -f OxiTide.app/Icon*
            mkdir -p $out/Applications
            cp -R OxiTide.app $out/Applications/
          '';
        })
      ];
    };
    tidal = {
      darwinCasks = [ "tidal" ];
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
