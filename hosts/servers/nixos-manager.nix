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

  tags = [ "tag:manager" ];

  # No options: terminal/neovim are always on (no enable options declared).
  options = { };

  config = { ... }: { };
}
