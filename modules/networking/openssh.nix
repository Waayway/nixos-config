{ hostPlatform, ... }:
# nix-darwin's `services.openssh` module only exposes `enable`. The
# workstation-flavored `settings.*`/`openFirewall`/`enableAllTerminfo`
# options don't exist there, so a `mkIf isLinux` on the value still
# triggers the "option doesn't exist" check on darwin. Build a single
# attrset per platform so darwin never sees the Linux-only assignments.
if hostPlatform.isDarwin then
  {
    services.openssh.enable = true;
  }
else
  {
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        X11Forwarding = true;
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = true;
      };
    };
    environment.enableAllTerminfo = true;
  }
