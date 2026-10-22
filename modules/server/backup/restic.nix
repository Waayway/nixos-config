{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Encrypted restic backups to the Hetzner Storage Box, driven from this host
# (nixos-manager). Design: docs/plans/2026-10-12-homelab-backup-design.md.
#
# Per repository, `restic-<name>.service`:
#   1. pings Healthchecks /start;
#   2. backs up local paths and SQLite copies of this host (host "nixos-manager");
#   3. copies a static, pinned restic to TrueNAS if needed and runs it there over
#      SSH against the newest `backup-*` ZFS snapshot of each dataset (host
#      "truenas"; modules/backup/restic-truenas.sh). The repo password goes over
#      stdin, the Storage Box key through the forwarded SSH agent: no secret is
#      stored on TrueNAS;
#   4. forget/prune and a partial `restic check` from here;
#   5. pings Healthchecks with the exit status (ExecStopPost).
# `restic-<name>` (on PATH) is restic with the repository set up, for restores.
let
  cfg = config.backup.restic;
  inherit (lib) mkOption types;
  secretPaths = config.services.onepassword-secrets.secretPaths;
  tn = config.truenas;

  # Runs on TrueNAS: the dynamically linked nixpkgs restic doesn't.
  resticStatic = "${pkgs.pkgsStatic.restic}/bin/.restic-wrapped";
  resticStaticName = "restic-${builtins.substring 11 32 (toString pkgs.pkgsStatic.restic)}";
  truenasRestic = "/root/nix-restic/${resticStaticName}";

  sb = cfg.storageBox;
  storageBoxKnownHosts = pkgs.writeText "storagebox-known-hosts" "[${sb.host}]:${toString sb.port} ${sb.hostKey}\n";
  truenasKnownHosts = pkgs.writeText "truenas-known-hosts" "${tn.host} ${tn.hostKey}\n";
  sftpCommand = "ssh -p ${toString sb.port} -i ${secretPaths.storageBoxKey} -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=60 -o UserKnownHostsFile=${storageBoxKnownHosts} -o StrictHostKeyChecking=yes ${sb.user}@${sb.host} -s sftp";

  repoUrl = name: "sftp:${sb.user}@${sb.host}:restic/${name}";

  # opnix wants camelCase secret names: store -> resticStore.
  passwordSecret =
    name: "restic" + lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (-1) name;

  repoEnv = name: {
    RESTIC_REPOSITORY = repoUrl name;
    RESTIC_PASSWORD_FILE = secretPaths.${passwordSecret name};
    RESTIC_CACHE_DIR = "/var/cache/restic-${name}";
  };

  # `restic-<name> snapshots`, `restic-<name> restore …`
  wrapper =
    name:
    pkgs.writeShellApplication {
      name = "restic-${name}";
      runtimeInputs = [
        pkgs.restic
        pkgs.openssh
      ];
      runtimeEnv = repoEnv name;
      text = ''exec restic -o sftp.command=${lib.escapeShellArg sftpCommand} "$@"'';
    };

  run =
    name: repo:
    pkgs.writeShellApplication {
      name = "restic-${name}-run";
      runtimeInputs = [
        pkgs.restic
        pkgs.openssh
        pkgs.sqlite
        pkgs.curl
        pkgs.coreutils
      ];
      runtimeEnv = repoEnv name;
      text = ''
        r() { restic -o sftp.command=${lib.escapeShellArg sftpCommand} "$@"; }

        ${lib.optionalString (repo.healthchecks == "full") ''
          curl -fsS -m 10 --retry 5 -o /dev/null "$(cat ${secretPaths.healthchecksUrl})/start" || true
        ''}

        if ! r cat config >/dev/null 2>&1; then
          echo "initialising repository ${repoUrl name}"
          r init
        fi

        # Locks of a restic that was killed (a Storage Box disconnect, Backrest
        # restarted mid-index) block prune/check until removed. `unlock` only
        # removes stale ones: older than 30 minutes, or from a process on this
        # host that no longer exists.
        r unlock

        ${lib.optionalString (repo.local.sqlite != { } || repo.local.paths != [ ]) ''
          echo "== local (nixos-manager)"
          state=/var/lib/restic-${name}
          rm -rf "$state/sqlite"
          mkdir -p "$state/sqlite"
          ${lib.concatStrings (
            lib.mapAttrsToList (db: path: ''
              sqlite3 ${lib.escapeShellArg path} ".backup '$state/sqlite/${db}.db'"
            '') repo.local.sqlite
          )}
          r backup --host nixos-manager --tag nix --tag ${name} --compression auto \
            "$state/sqlite" ${lib.escapeShellArgs repo.local.paths}
        ''}

        ${lib.optionalString (repo.truenas != [ ]) ''
          echo "== truenas"
          # tn [ssh options…] -- <remote command>
          tn() {
            local opts=()
            while [ $# -gt 0 ] && [ "$1" != -- ]; do
              opts+=("$1")
              shift
            done
            shift
            ssh -i ${secretPaths.truenasAutomationKey} -o IdentitiesOnly=yes -o BatchMode=yes \
              -o UserKnownHostsFile=${truenasKnownHosts} -o StrictHostKeyChecking=yes \
              -o ServerAliveInterval=60 "''${opts[@]}" ${tn.user}@${tn.host} "$@"
          }
          # The pinned static restic; older ones in the same directory go.
          if ! tn -- sudo test -x ${truenasRestic}; then
            echo "copying ${resticStaticName} to TrueNAS"
            tn -- 'sudo rm -rf /root/nix-restic && sudo install -D -m 0700 /dev/stdin ${truenasRestic}' \
              <${resticStatic}
          fi

          eval "$(ssh-agent -s)" >/dev/null
          trap 'ssh-agent -k >/dev/null' EXIT
          ssh-add -q ${secretPaths.storageBoxKey}

          args=$(printf '%q ' ${truenasRestic} ${lib.escapeShellArg (repoUrl name)} \
            ${
              lib.escapeShellArgs [
                sb.user
                sb.host
                (toString sb.port)
                "[${sb.host}]:${toString sb.port} ${sb.hostKey}"
                repo.snapshotPrefix
                (toString repo.maxSnapshotAgeHours)
                name
              ]
            } ${lib.escapeShellArgs repo.truenas})
          script=$(printf '%q' "$(cat ${./restic-truenas.sh})")
          printf '%s\n' "$(cat "$RESTIC_PASSWORD_FILE")" |
            tn -A -- "sudo SSH_AUTH_SOCK=\"\$SSH_AUTH_SOCK\" bash -c $script restic-truenas $args"
        ''}

        echo "== forget/prune"
        r forget --prune ${lib.escapeShellArgs repo.pruneOpts}

        echo "== check"
        r check ${lib.escapeShellArgs repo.checkOpts}
      '';
    };

  # ExecStopPost: report the run to Healthchecks with its exit status and log.
  ping =
    name: repo:
    pkgs.writeShellScript "restic-${name}-ping" ''
      export PATH=${
        lib.makeBinPath [
          pkgs.curl
          pkgs.coreutils
          pkgs.systemd
        ]
      }
      if [ "$SERVICE_RESULT" = success ]; then code=0; else code=''${EXIT_STATUS:-1}; fi
      case $code in "" | *[!0-9]*) code=1 ;; esac
      ${lib.optionalString (repo.healthchecks == "failures") ''[ "$code" = 0 ] && exit 0''}
      body=$(journalctl _SYSTEMD_INVOCATION_ID="$INVOCATION_ID" -o cat --no-pager | tail -c 60000)
      curl -fsS -m 10 --retry 5 -o /dev/null --data-raw "$body" \
        "$(cat ${secretPaths.healthchecksUrl})/$code" || true
    '';

  repoType = types.submodule (
    { name, ... }:
    {
      options = {
        passwordReference = mkOption {
          type = types.str;
          default = "op://Homelab/restic-${name}/password";
        };
        truenas = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Datasets on TrueNAS, backed up from their newest snapshot
            (`store/internal`), and absolute paths backed up live
            (`/data/freenas-v1.db`; `*.db` is copied with sqlite first).
          '';
        };
        local = {
          paths = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          sqlite = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "SQLite databases on this host, by name; copied with `.backup`.";
          };
        };
        snapshotPrefix = mkOption {
          type = types.str;
          default = "backup-";
        };
        maxSnapshotAgeHours = mkOption {
          type = types.ints.positive;
          default = 26;
        };
        timerConfig = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        pruneOpts = mkOption {
          type = types.listOf types.str;
          default = [
            "--keep-daily"
            "7"
            "--keep-weekly"
            "4"
            "--keep-monthly"
            "12"
          ];
        };
        checkOpts = mkOption {
          type = types.listOf types.str;
          # A different random 1% each run; the whole repository is read over time.
          default = [ "--read-data-subset=1%" ];
        };
        healthchecks = mkOption {
          type = types.enum [
            "full"
            "failures"
            "none"
          ];
          default = "full";
          description = "full: /start and every result; failures: only failed runs.";
        };
      };
    }
  );
in
lib.optionalAttrs hostPlatform.isLinux {
  options.backup.restic = {
    enable = lib.mkEnableOption "restic backups to the Storage Box";
    storageBox = {
      user = mkOption { type = types.str; };
      host = mkOption { type = types.str; };
      port = mkOption {
        type = types.port;
        default = 23;
      };
      hostKey = mkOption {
        type = types.str;
        description = "The Storage Box's SSH host key (`<type> <base64>`).";
      };
      keyReference = mkOption {
        type = types.str;
        default = "op://Homelab/storagebox-backup/private key?ssh-format=openssh";
      };
    };
    healthchecksReference = mkOption {
      type = types.str;
      default = "op://Homelab/healthchecks.io/url";
    };
    repos = mkOption {
      type = types.attrsOf repoType;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.any (r: r.truenas != [ ]) (lib.attrValues cfg.repos) -> tn.enable;
        message = "backup.restic: repos with `truenas` need truenas.enable (host, user, key).";
      }
    ];

    services.onepassword-secrets.secrets = lib.mkMerge (
      [
        {
          storageBoxKey = {
            reference = sb.keyReference;
            mode = "0400";
            owner = "root";
          };
          healthchecksUrl = {
            reference = cfg.healthchecksReference;
            mode = "0400";
            owner = "root";
          };
        }
      ]
      ++ lib.mapAttrsToList (name: repo: {
        ${passwordSecret name} = {
          reference = repo.passwordReference;
          mode = "0400";
          owner = "root";
        };
      }) cfg.repos
    );

    environment.systemPackages = [
      pkgs.restic
    ]
    ++ lib.mapAttrsToList (name: _: wrapper name) cfg.repos;

    systemd.services = lib.mapAttrs' (
      name: repo:
      lib.nameValuePair "restic-${name}" {
        description = "restic backup: ${name}";
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "opnix-secrets.service"
        ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (run name repo);
          ExecStopPost = ping name repo;
          StateDirectory = "restic-${name}";
          CacheDirectory = "restic-${name}";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      }
    ) cfg.repos;

    systemd.timers = lib.mapAttrs' (
      name: repo:
      lib.nameValuePair "restic-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          Persistent = "true";
          RandomizedDelaySec = "10min";
        }
        // repo.timerConfig;
      }
    ) cfg.repos;
  };
}
