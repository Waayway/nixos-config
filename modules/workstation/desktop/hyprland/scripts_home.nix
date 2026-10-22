{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  xdg.configFile."hypr/scripts".source = ./scripts;
})
