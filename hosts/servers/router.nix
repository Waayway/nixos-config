{
  system = "x86_64-linux";
  user = {
    name = "router";
    fullname = "Router";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.110";
    prefixLength = 24;
  };

  tags = [ "tag:router" ];

  fleet = true;

  # The front door: Traefik for every route in the flake (modules/server/homelab/router/).
  options = {
    homelab.router.enable = true;
  };

  config = { ... }: { };
}
