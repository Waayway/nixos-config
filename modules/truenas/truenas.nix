{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# TrueNAS (VM 130) as code: snapshot tasks, dataset properties, cron jobs and NFS
# shares are declared here and applied from the host that enables this module
# (nixos-manager) by `truenas-reconcile`, over SSH as the TrueNAS user
# `automation` (passwordless sudo, key in 1Password: Homelab/truenas-automation).
# Pools, datasets and that user stay manual; see docs/homelab.md. Runs on every
# switch that changes the declared state and once a day; `sudo truenas-reconcile
# check` shows pending changes without making them.
let
  cfg = config.truenas;
  inherit (lib) mkOption types;

  schedule = defaults: {
    minute = mkOption {
      type = types.str;
      default = defaults.minute or "00";
    };
    hour = mkOption {
      type = types.str;
      default = defaults.hour or "*";
    };
    dom = mkOption {
      type = types.str;
      default = "*";
    };
    month = mkOption {
      type = types.str;
      default = "*";
    };
    dow = mkOption {
      type = types.str;
      default = "*";
      description = "Day of week, 1 (Monday) to 7 (Sunday).";
    };
  };

  snapshotTask = types.submodule {
    options = {
      dataset = mkOption { type = types.str; };
      recursive = mkOption {
        type = types.bool;
        default = false;
      };
      exclude = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      namingSchema = mkOption {
        type = types.str;
        default = "auto-%Y-%m-%d_%H-%M";
      };
      keep = {
        value = mkOption { type = types.ints.positive; };
        unit = mkOption {
          type = types.enum [
            "HOUR"
            "DAY"
            "WEEK"
            "MONTH"
            "YEAR"
          ];
        };
      };
      schedule = schedule { };
      allowEmpty = mkOption {
        type = types.bool;
        default = true;
      };
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  cronJob = types.submodule {
    options = {
      description = mkOption { type = types.str; };
      command = mkOption { type = types.str; };
      user = mkOption {
        type = types.str;
        default = "root";
      };
      schedule = schedule { };
      hideStdout = mkOption {
        type = types.bool;
        default = true;
      };
      hideStderr = mkOption {
        type = types.bool;
        default = false;
        description = "Errors are mailed through TrueNAS's alert e-mail unless hidden.";
      };
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  nfsShare = types.submodule {
    options = {
      path = mkOption { type = types.str; };
      hosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      networks = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      readOnly = mkOption {
        type = types.bool;
        default = false;
      };
      maprootUser = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      maprootGroup = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  # The middleware's field names; "[nix] <name>" marks what this module owns.
  desired = {
    snapshotTasks = lib.mapAttrsToList (_: t: {
      inherit (t)
        dataset
        recursive
        exclude
        enabled
        ;
      naming_schema = t.namingSchema;
      lifetime_value = t.keep.value;
      lifetime_unit = t.keep.unit;
      allow_empty = t.allowEmpty;
      schedule = t.schedule;
    }) cfg.snapshotTasks;
    datasets = lib.mapAttrsToList (id: d: {
      inherit id;
      props = {
        inherit (d) snapdir;
      };
    }) cfg.datasets;
    cronJobs = lib.mapAttrsToList (name: j: {
      inherit name;
      spec = {
        description = "[nix] ${name}: ${j.description}";
        inherit (j)
          command
          user
          enabled
          schedule
          ;
        stdout = j.hideStdout;
        stderr = j.hideStderr;
      };
    }) cfg.cronJobs;
    nfsShares = lib.mapAttrsToList (name: s: {
      inherit name;
      spec = {
        comment = "[nix] ${name}";
        inherit (s)
          path
          hosts
          networks
          enabled
          ;
        ro = s.readOnly;
      }
      // lib.optionalAttrs (s.maprootUser != null) { maproot_user = s.maprootUser; }
      // lib.optionalAttrs (s.maprootGroup != null) { maproot_group = s.maprootGroup; };
    }) cfg.nfsShares;
  };
  desiredFile = pkgs.writeText "truenas-desired.json" (builtins.toJSON desired);

  reconcile = pkgs.writeShellApplication {
    name = "truenas-reconcile";
    runtimeInputs = [
      pkgs.openssh
      pkgs.jq
      pkgs.coreutils
    ];
    runtimeEnv = {
      TRUENAS_HOST = cfg.host;
      TRUENAS_USER = cfg.user;
      TRUENAS_KEY = config.services.onepassword-secrets.secretPaths.truenasAutomationKey;
      TRUENAS_KNOWN_HOSTS = pkgs.writeText "truenas-known-hosts" "${cfg.host} ${cfg.hostKey}\n";
      DESIRED = desiredFile;
    };
    # The $… in single quotes are jq variables.
    excludeShellChecks = [ "SC2016" ];
    text = builtins.readFile ./reconcile.sh;
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.truenas = {
    enable = lib.mkEnableOption "managing TrueNAS from this host";
    host = mkOption {
      type = types.str;
      default = "10.0.10.130";
    };
    user = mkOption {
      type = types.str;
      default = "automation";
    };
    hostKey = mkOption {
      type = types.str;
      description = "TrueNAS's SSH host key (`<type> <base64>`).";
    };
    keyReference = mkOption {
      type = types.str;
      default = "op://Homelab/truenas-automation/private key?ssh-format=openssh";
    };
    snapshotTasks = mkOption {
      type = types.attrsOf snapshotTask;
      default = { };
    };
    datasets = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.snapdir = mkOption {
            type = types.nullOr (
              types.enum [
                "VISIBLE"
                "HIDDEN"
              ]
            );
            default = null;
          };
        }
      );
      default = { };
      description = "Properties of existing datasets, by dataset name.";
    };
    cronJobs = mkOption {
      type = types.attrsOf cronJob;
      default = { };
    };
    nfsShares = mkOption {
      type = types.attrsOf nfsShare;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.onepassword-secrets.secrets.truenasAutomationKey = {
      reference = cfg.keyReference;
      mode = "0400";
      owner = "root";
      services = [ "truenas-reconcile" ];
    };

    environment.systemPackages = [ reconcile ];

    systemd.services.truenas-reconcile = {
      description = "Make TrueNAS match its declared state";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # Re-run when a switch changes the declared state.
      restartTriggers = [ desiredFile ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe reconcile} apply";
      };
    };

    # The unit above stays "active" after a switch, so the daily run (which also
    # undoes changes made in the UI) is a separate one.
    systemd.services.truenas-reconcile-daily = {
      description = "Make TrueNAS match its declared state (daily)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe reconcile} apply";
      };
    };
    systemd.timers.truenas-reconcile-daily = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 05:00";
        RandomizedDelaySec = "15min";
        Persistent = true;
      };
    };
  };
}
