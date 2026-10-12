{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  # Workstation-only: skipped on servers (type = "server").
  config = lib.mkIf (!hostPlatform.isServer) {
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };
}
