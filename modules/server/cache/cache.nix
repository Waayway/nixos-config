{
  config,
  lib,
  hostPlatform,
  ...
}:
# The build cache VM (docs/plans/2026-10-29-build-cache-design.md): the Lodestar
# server builds on it over ssh-ng and publishes a file binary cache to the TrueNAS
# share, which nginx serves to the router only (the router fronts it for the fleet).
#
# This host must NOT substitute from its own cache: it would wait on its own nginx
# while building the paths it publishes. The client module that adds the cache as a
# substituter on Linux hosts skips when `services.lodestar-cache.enable` is true.
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.cache.enable = lib.mkEnableOption "the build cache host (Lodestar builder + binary cache on a TrueNAS share)";

  config = lib.mkIf config.homelab.cache.enable {
    boot.supportedFilesystems = [ "nfs" ];

    # The dataset store/internal/nix-cache is owned 1500:100 on TrueNAS, so the user
    # the Lodestar server logs in as needs that uid and the `users` group.
    users.users.lodestar = {
      uid = 1500;
      group = "users";
    };

    # No x-systemd.idle-timeout (see modules/server/homelab/storage.nix). nfsvers=4.2:
    # the cache scripts flock over NFS, which needs v4. nofail: a cache outage (TrueNAS
    # down) must not stop the builder from booting.
    fileSystems."/mnt/nix-cache" = {
      device = "10.0.10.130:/mnt/store/internal/nix-cache";
      fsType = "nfs";
      options = [
        "_netdev"
        "nofail"
        "nfsvers=4.2"
        "x-systemd.automount"
      ];
    };

    # Served to the fleet through the router, on the tailnet only (no gate: nix clients
    # cannot sign in; the store is public data signed by the cache key).
    homelab.routes.cache = {
      host = "cache.vanwaaij.com";
      backend = "http://10.0.10.171:80";
      public = false;
      tailnet.enable = true;
    };

    services.onepassword-secrets.secrets.nixCacheSigningKey = {
      reference = "op://Homelab/nix-cache-signing-key/credential";
      owner = "lodestar";
      mode = "0400";
    };

    services.lodestar-cache = {
      enable = true;
      user = "lodestar";
      cacheDir = "/mnt/nix-cache";
      signingKeyFile = config.services.onepassword-secrets.secretPaths.nixCacheSigningKey;
      listen.port = 80;
      # Public half of the 1Password item lodestar-builder-key.
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOi8oAr+1eUEmpfy9C8PEng763eBMyFA0RHVLnrx+Jhg lodestar-builder"
      ];
      # The router only.
      allowedClients = [ "10.0.10.110" ];
    };
  };
}
