{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Workstation-only: skipped on servers (type = "server").
  config = lib.mkIf (!hostPlatform.isServer) {
    services.power-profiles-daemon = {
      enable = true;
    };
    # Battery state for the Quickshell bar (desktop/quickshell/).
    services.upower.enable = true;
  };
}
