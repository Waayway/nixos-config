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

  # Kanidm at id.vanwaaij.com (modules/identity/); online backups to TrueNAS
  # store/authentication, exported to this VM only (modules/truenas/homelab.nix).
  options = {
    homelab.identity = {
      enable = true;
      domain = "id.vanwaaij.com";
      backupNfs = "10.0.10.130:/mnt/store/authentication";
    };
  };

  config = { ... }: { };
}
