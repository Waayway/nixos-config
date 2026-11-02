{
  system = "x86_64-linux";
  user = {
    name = "cache";
    fullname = "Cache";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.171";
    prefixLength = 24;
  };

  tags = [ "tag:cache" ];

  fleet = true;

  # Lodestar's builder and the fleet's binary cache (modules/server/cache/); the cache
  # itself lives on a TrueNAS share mounted at /mnt/nix-cache.
  options = {
    homelab.cache.enable = true;
  };

  config = { ... }: { };
}
