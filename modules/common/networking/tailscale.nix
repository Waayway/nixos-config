{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux {
  services.tailscale = {
    enable = true;
    # Used by tailscaled-autoconnect (servers, with an auth key). Workstations
    # turn SSH on in workstation/networking/tailscale.nix.
    extraUpFlags = [ "--ssh" ];
  };
}
