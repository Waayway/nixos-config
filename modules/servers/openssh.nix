{ lib, ... }:
{
  # base/openssh.nix enables sshd with workstation-friendly defaults
  # (PasswordAuthentication=true, X11Forwarding=true). Servers harden that.
  services.openssh.settings = {
    PasswordAuthentication       = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
    X11Forwarding                = lib.mkForce false;
  };
}
