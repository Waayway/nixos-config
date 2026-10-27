{
  lib,
  upkgs,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  services.tailscale = {
    enable = true;
    # From unstable for TS-2026-013 (fixed in 1.104.2; nixos-26.05 has 1.98.10). Drop
    # once stable's tailscale is at least that.
    package = upkgs.tailscale;
    # Used by tailscaled-autoconnect (servers, with an auth key). Workstations
    # turn SSH on in workstation/networking/tailscale.nix.
    extraUpFlags = [ "--ssh" ];
  };
}
