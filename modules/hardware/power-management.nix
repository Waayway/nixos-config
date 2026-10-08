{ pkgs, lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  services.power-profiles-daemon = { enable = true; };
})
