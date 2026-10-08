{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
})
