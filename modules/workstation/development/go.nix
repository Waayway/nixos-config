{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.mkIf (!hostPlatform.isServer) {
    environment.systemPackages = with pkgs; [
      go_1_25
      gotools
      templ
      go-task
    ];
  };
}
