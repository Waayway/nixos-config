{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  # Port 22 is opened by services.openssh.openFirewall (servers only).
  networking.firewall.enable = true;
})
