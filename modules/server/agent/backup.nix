{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Nightly copy of the Hermes state (memory, skills, sessions, the OAuth logins) to
# TrueNAS store/internal/iris at 01:30, before the 02:00 snapshot that the restic
# `store` repo reads (modules/server/backup/homelab.nix): one backup setup for the
# homelab, like Kanidm's. SQLite files are copied with `.backup` (consistent while the
# gateway writes); the rest is tarred around them. Seven archives are kept. Restore:
# docs/agent.md.
let
  h = config.services.hermes-agent;
  dir = "/var/lib/hermes-backup";
  script = ''
    set -eu
    umask 077
    stamp=$(date +%Y-%m-%d)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cd ${h.stateDir}
    find . -name '*.db' -type f | while read -r db; do
      mkdir -p "$tmp/$(dirname "$db")"
      sqlite3 "$db" ".backup '$tmp/$db'"
    done
    # The gateway writes logs and sessions all the time: "file changed as we read it"
    # (exit 1) is expected; anything else is a real failure.
    tar --create --file "$tmp/files.tar" --warning=no-file-changed \
      --exclude='*.db' --exclude='*.db-wal' --exclude='*.db-shm' --exclude='*.db-journal' \
      --exclude='./.cache' --exclude='./.npm' . || [ $? -eq 1 ]
    tar --create --gzip --file "${dir}/hermes-$stamp.tar.gz.part" -C "$tmp" .
    mv "${dir}/hermes-$stamp.tar.gz.part" "${dir}/hermes-$stamp.tar.gz"
    ls -1t ${dir}/hermes-*.tar.gz | tail -n +8 | xargs -r rm -f
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.agent.enable {
    # Fixed: the share is root squashed and its dataset owned by this uid.
    users.users.${h.user}.uid = 950;

    # No x-systemd.idle-timeout (modules/server/homelab/storage.nix); nofail: TrueNAS
    # down must not stop iris from booting.
    boot.supportedFilesystems = [ "nfs" ];
    fileSystems.${dir} = {
      device = "10.0.10.130:/mnt/store/internal/iris";
      fsType = "nfs";
      options = [
        "_netdev"
        "nofail"
        "nfsvers=4.2"
        "x-systemd.automount"
      ];
    };

    systemd.services.hermes-backup = {
      description = "Copy the Hermes state to TrueNAS";
      unitConfig.RequiresMountsFor = [ dir ];
      path = with pkgs; [
        sqlite
        gnutar
        gzip
        findutils
        coreutils
      ];
      inherit script;
      serviceConfig = {
        Type = "oneshot";
        User = h.user;
        Group = h.group;
      };
    };
    systemd.timers.hermes-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 01:30";
        Persistent = true;
      };
    };
  };
}
