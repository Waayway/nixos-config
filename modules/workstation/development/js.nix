{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.mkIf (!hostPlatform.isServer) {
    environment.systemPackages = with pkgs; [
      nodejs_22
      deno
      bun
    ];
  };
}
