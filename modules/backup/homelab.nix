{
  config,
  lib,
  hostPlatform,
  ...
}:
# The homelab's restic repositories (modules/backup/restic.nix), on the host
# that sets `backup.restic.enable` (nixos-manager). Everything on the ZFS pools
# except the VM disks (store/proxmox-vms); database dumps land in
# store/internal/db-dumps before the 02:00 snapshot.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.backup.restic.enable {
    backup.restic = {
      # Hetzner Storage Box, sub-account in 1Password: Homelab/Hetzner Personal storage.
      storageBox = {
        user = "u592252-sub2";
        host = "u592252-sub2.your-storagebox.de";
        hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
      };

      repos.store = {
        truenas = [
          "store/internal"
          "store/shares"
          "archive/internal"
          # TrueNAS's configuration database and the key that decrypts its secrets.
          "/data/freenas-v1.db"
          "/data/pwenc_secret"
        ];
        local.sqlite.lodestar = "/var/lib/lodestar-server/lodestar.db";
        timerConfig.OnCalendar = "*-*-* 02:30";
      };

      # Mostly the Jellyfin library: large, slow-changing, replaceable.
      repos.archive = {
        truenas = [ "archive/shares" ];
        # The snapshot is daily; the backup weekly.
        timerConfig.OnCalendar = "Sun 03:00";
        pruneOpts = [
          "--keep-weekly"
          "4"
          "--keep-monthly"
          "6"
        ];
        checkOpts = [ "--read-data-subset=0.5%" ];
        # One Healthchecks check (the daily store run); archive only reports failures.
        healthchecks = "failures";
      };
    };
  };
}
