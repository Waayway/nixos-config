{
  config,
  lib,
  hostPlatform,
  ...
}:
# The homelab's TrueNAS (10.0.10.130) on any VM: fast storage at /store, slow
# shares at /archive. Mounted on first access, so boot never waits for the NAS.
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.storage.enable = lib.mkEnableOption "TrueNAS NFS mounts at /store and /archive";

  config = lib.mkIf config.homelab.storage.enable {
    boot.supportedFilesystems = [ "nfs" ];

    fileSystems =
      lib.mapAttrs
        (_: device: {
          inherit device;
          fsType = "nfs";
          options = [
            "_netdev"
            "nofail"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
          ];
        })
        {
          "/store" = "10.0.10.130:/mnt/store/internal";
          "/archive" = "10.0.10.130:/mnt/archive/shares";
        };
  };
}
