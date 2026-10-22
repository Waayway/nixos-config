{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux {
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };
}
