args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "media";
  apps = {
    spotify = {
      linux = [ pkgs.spotify ];
      darwinCasks = [ "spotify" ];
    };
    spot.linux = [ pkgs.spot ];
    sone.linux = [ pkgs.sone ];
    tidal.darwinCasks = [ "tidal" ];
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
