{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!hostPlatform.isServer) {
    environment.systemPackages = with pkgs; [ moonlight-qt ];
  };
}
