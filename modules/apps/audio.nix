args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "audio";
  # Pro audio / show-control rig. Proprietary vendor installers, darwin only.
  # Manual-only: Avantis Director, Dante Virtual Soundcard, Dante Activator/Updater.
  apps = {
    reaper.darwinCasks = [ "reaper" ];
    qlab.darwinCasks = [ "qlab" ];
    companion.darwinCasks = [ "companion" ]; # Bitfocus Companion
    dante.darwinCasks = [ "dante-controller" ];
    wireless-workbench.darwinCasks = [ "wireless-workbench" ]; # Shure WWB
    focusrite.darwinCasks = [ "focusrite-control-2" ];
  };
}
