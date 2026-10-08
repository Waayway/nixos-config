{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux ({
  environment.systemPackages = with pkgs; [ libreoffice ];
})
