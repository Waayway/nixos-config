{
  system = "x86_64-linux";
  user = {
    name = "iris";
    fullname = "Iris";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.101";
    prefixLength = 24;
  };

  tags = [ "tag:iris" ];

  fleet = true;

  # Hermes Agent, a Discord bot with its dashboard at agent.vanwaaij.com
  # (modules/server/agent/, docs/agent.md). Not `hermes`: that's the Framework laptop.
  options = {
    homelab.agent.enable = true;
  };

  config = { ... }: { };
}
