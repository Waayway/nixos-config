{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  home.file.".wallpapers".source = ../../../wallpapers;
})
