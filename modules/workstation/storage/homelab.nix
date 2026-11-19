{
  config,
  lib,
  hostPlatform,
  ...
}:
# The homelab's TrueNAS (10.0.10.130) on a workstation: fast storage at /store, slow
# shares at /archive, the same paths and exports the servers use
# (modules/server/homelab/storage.nix). Mounted on first access, so boot and the desktop
# never wait for the NAS, and a missing NAS (away from the LAN and the tailnet's subnet
# route) costs 15 seconds on first access, not a stuck file manager.
# No x-systemd.idle-timeout, same as the servers: a mount that expires under an open
# file is worse than one that stays.
lib.optionalAttrs hostPlatform.isLinux {
  options.workstation.storage.homelab.enable =
    lib.mkEnableOption "TrueNAS NFS mounts at /store and /archive";

  config = lib.mkIf (config.workstation.storage.homelab.enable && !hostPlatform.isServer) {
    boot.supportedFilesystems = [ "nfs" ];

    fileSystems =
      lib.mapAttrs
        (_: device: {
          inherit device;
          fsType = "nfs";
          options = [
            "_netdev"
            "nofail"
            "noatime"
            "x-systemd.automount"
            "x-systemd.mount-timeout=15s"
          ];
        })
        {
          "/store" = "10.0.10.130:/mnt/store/internal";
          "/archive" = "10.0.10.130:/mnt/archive/shares";
        };
  };
}
