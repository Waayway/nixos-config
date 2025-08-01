{ pkgs, ... }:
{
  programs.hyprland.enable = true;
  environment.sessionVariables = {
    # Fix for Electron Apps to say to use wayland
    NIXOS_OZONE_WL = "1";
  };

  environment.systemPackages = with pkgs; [
    # --Utils and more--
    ### Display
    wlr-randr
    brightnessctl
    hyprland-monitor-attached

    ### Sound
    playerctl
    pamixer
    pavucontrol

    ### Other
    networkmanagerapplet

    # --Screenshots--
    grim
    slurp

    # --Overlays Bars and more--
    waybar
    wlogout
    rofi-wayland

    # HyprCursor cursor
    rose-pine-hyprcursor

    # Other applications
    nemo
    nemo-fileroller

    # Hypr Ecosystem
    pkgs.hyprpicker
    pkgs.hyprpaper
  ];
}
