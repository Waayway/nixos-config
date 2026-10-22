{ lib, hostPlatform, ... }:
# nix-darwin's `services.openssh` module only exposes `enable`, so each
# platform gets its own attrset. No inbound SSH on workstations (they are
# reached through Tailscale SSH); servers enable sshd in
# server/networking/openssh.nix.
if hostPlatform.isDarwin then
  {
    # No inbound SSH (Remote Login) on the Macs.
    services.openssh.enable = false;
  }
else
  {
    services.openssh.enable = lib.mkDefault false;
  }
