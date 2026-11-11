{
  lib,
  config,
  upkgs,
  hostPlatform,
  ...
}:
let
  # 1.104.6 (magicsock EADDRNOTAVAIL retries, wireguard-go duplicate handshake fix) ahead
  # of nixpkgs. Only while the pinned unstable is older; drop once it has 1.104.6.
  pinned = "1.104.6";
  tailscale =
    if lib.versionOlder upkgs.tailscale.version pinned then
      upkgs.tailscale.overrideAttrs {
        version = pinned;
        src = upkgs.fetchFromGitHub {
          owner = "tailscale";
          repo = "tailscale";
          tag = "v${pinned}";
          hash = "sha256-oF3izFlknJRuEYp3rw1urN4XKZPvjtda6lsIw9arRvs=";
        };
        # go.mod bumped wireguard-go in 1.104.6.
        vendorHash = "sha256-IJ0m56UP0RyMBE5eQeQ082EMJZfvrgE37lfPHE2ujCA=";
      }
    else
      upkgs.tailscale;
in
lib.optionalAttrs hostPlatform.isLinux {
  services.tailscale = {
    enable = true;
    # From unstable for TS-2026-013 (fixed in 1.104.2; nixos-26.05 has 1.98.10). Drop
    # once stable's tailscale is at least that.
    package = tailscale;
    # Used by tailscaled-autoconnect (servers, with an auth key). Workstations
    # turn SSH on in workstation/networking/tailscale.nix.
    extraUpFlags = [ "--ssh" ];
  };

  # Reported to Lodestar, which compares it with upstream (Software updates).
  services.lodestar-agent.versions.tailscale = config.services.tailscale.package.version;
}
