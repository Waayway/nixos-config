{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Workstation-only: skipped on servers (type = "server").
  config = lib.mkIf (!hostPlatform.isServer) {
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

      ### Sound
      playerctl
      pamixer
      pavucontrol

      ### Other
      networkmanagerapplet

      # --Screenshots--
      grim
      slurp

      # --Launcher-- (bar and notifications: Quickshell, desktop/quickshell/)
      rofi
      libnotify

      # HyprCursor cursor
      rose-pine-hyprcursor

      # Other applications
      nemo
      nemo-fileroller

      # Hypr Ecosystem
      hyprpicker
      hyprpaper
      hypridle
    ];

    # hyprlock with its PAM service. hypridle, hyprlock and hyprpaper are
    # configured in desktop/hyprland/config/ and started by Hyprland.
    programs.hyprlock.enable = true;
  };
}
