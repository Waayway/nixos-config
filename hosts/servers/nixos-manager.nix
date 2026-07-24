{
  system = "x86_64-linux";
  user = {
    name = "manager";
    fullname = "Nixos Manager";
  };

  type = "server";
  use_default_hardware = true;
  is_home_server = true;

  net_interface = {
    ip = "10.0.10.170";
    prefixLength = 24;
  };

  tailscale_tags = [ "tag:manager" ];

  options = {

  };

  config = { ... }: { };
}
