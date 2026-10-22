{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.mkIf (!hostPlatform.isServer) {
    environment.systemPackages = with pkgs; [
      rustup
    ];
  };
}
