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
    oxitide.flatpak = [
      {
        flatpakref = "https://flatpak.oxitide.com/oxitide.flatpakref";
        sha256 = "1yhpqlriisy0dvgg53sxmyfsxmvbypf1fz2rpgp0dvhn18fr0346";
      }
    ];
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
