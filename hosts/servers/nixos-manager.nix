{
  system = "x86_64-linux";
  user = {
    name = "manager";
    fullname = "Nixos Manager";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.170";
    prefixLength = 24;
  };

  tailscaleTags = [ "tag:manager" ];

  options = {
    workstation = {
      terminal.enable = true;
      neovim.enable = true;
    };
    server = { };
  };

  config = { ... }: { };
}
