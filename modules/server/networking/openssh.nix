{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf hostPlatform.isServer {
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    environment.enableAllTerminfo = true;
  };
}
