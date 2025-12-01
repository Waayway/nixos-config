{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
		fragments
		audacity
    gnome-calculator
    obsidian
    handbrake
    gparted
  ];
}
