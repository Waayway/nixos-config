{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Workstation-only: skipped on servers (type = "server").
  config = lib.mkIf (!hostPlatform.isServer) {
    services.xserver.enable = true;
    environment.systemPackages = with pkgs; [ wl-clipboard ];
  };
}
