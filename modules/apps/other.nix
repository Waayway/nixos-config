{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux ({
  environment.systemPackages = with pkgs; [
    fragments
    audacity
    gnome-calculator
    obsidian
    handbrake
    gparted
  ];
})
