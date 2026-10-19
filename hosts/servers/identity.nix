{
  system = "x86_64-linux";
  user = {
    name = "identity";
    fullname = "Identity";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.111";
    prefixLength = 24;
  };

  tags = [ "tag:identity" ];

  fleet = true;

  # Kanidm at id.vanwaaij.com (modules/identity/); online backups to /store/kanidm.
  options = {
    homelab.storage.enable = true;
    homelab.identity = {
      enable = true;
      domain = "id.vanwaaij.com";
    };
  };

  config = { ... }: { };
}
