{
  config,
  lib,
  hostPlatform,
  ...
}:
# The homelab's TrueNAS (VM 130), applied by modules/server/truenas/truenas.nix from the
# host that sets `truenas.enable` (nixos-manager). Inventory: docs/homelab.md.
let
  smart =
    type:
    ''for d in /dev/disk/by-id/ata-*; do case "$d" in *-part*) ;; *) /usr/sbin/smartctl -t ${type} "$d" >/dev/null ;; esac; done'';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.truenas.enable {
    truenas = {
      # Also read by the monitor (modules/server/monitoring/exporters.nix).
      hostKey = lib.fileContents ./host-key.pub;

      # Read by the restic backups (modules/server/backup/homelab.nix) from
      # .zfs/snapshot; kept 3 days for quick local restores too.
      snapshotTasks =
        lib.genAttrs
          [
            "store"
            "archive"
          ]
          (pool: {
            dataset = pool;
            recursive = true;
            exclude = lib.optional (pool == "store") "store/proxmox-vms";
            namingSchema = "backup-%Y-%m-%d_%H-%M";
            keep = {
              value = 3;
              unit = "DAY";
            };
            schedule = {
              minute = "00";
              hour = "02";
            };
          });

      datasets =
        lib.genAttrs
          [
            "store/internal"
            "store/shares"
            "archive/internal"
            "archive/shares"
          ]
          (_: {
            snapdir = "VISIBLE";
          });

      # /archive on the VMs (modules/server/homelab/storage.nix); like the jellyfin
      # share, open to the LAN.
      nfsShares.archive-shares.path = "/mnt/archive/shares";

      # Kanidm's online backups (modules/server/identity/kanidm.nix, `backupNfs`), for the
      # identity VM only; root squashed, the dataset's root is 65534:65534 0700.
      nfsShares.authentication = {
        path = "/mnt/store/authentication";
        hosts = [ "10.0.10.111" ];
      };

      # TrueNAS 26 has no SMART test schedules of its own. Errors go out by mail.
      cronJobs = {
        smart-short = {
          description = "SMART short self-test, all data disks";
          command = smart "short";
          schedule = {
            hour = "03";
            dow = "6";
          };
        };
        smart-long = {
          description = "SMART long self-test, all data disks";
          command = smart "long";
          schedule = {
            hour = "04";
            dom = "1";
          };
        };
      };
    };
  };
}
