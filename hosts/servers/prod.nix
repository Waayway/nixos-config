{
  system = "x86_64-linux";
  user = {
    name = "prod";
    fullname = "Production";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.100";
    prefixLength = 24;
  };

  tags = [ "tag:prod" ];

  fleet = true;

  options = {
    homelab.storage.enable = true;
    # q35 (for the Arc's PCIe passthrough) puts virtio-net on the PCIe bridge:
    # the NIC is enp6s18, not the template's ens18.
    homelab.lan.interface = "enp6s18";
    # Live since the cutover (2026-10-19): the router sends the internet here.
    homelab.nextcloud = {
      enable = true;
      live = true;
    };
    homelab.jellyfin = {
      enable = true;
      live = true;
      configDir = "/store/jellyfin/config";
      # Intel Arc A380 passed through from pve (mapping ArcA380, q35).
      gpu = true;
    };
    homelab.immich = {
      enable = true;
      live = true;
      gpu = true;
    };
  };

  config = { ... }: { };
}
