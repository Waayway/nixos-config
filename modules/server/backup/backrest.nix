{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Backrest (web UI for restic) over the restic repositories of
# modules/server/backup/restic.nix: browse snapshots, restore files. Read-only in
# spirit: no plans, no prune/check schedules; backups stay in `restic-<name>`.
# The config is generated on every start (repos, login), so UI edits don't
# survive a restart. A repo appears once it exists (it needs its restic ID).
# Login: 1Password Homelab/backrest. Tailnet only.
let
  cfg = config.backup.backrest;
  restic = config.backup.restic;
  sb = restic.storageBox;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  knownHosts = pkgs.writeText "storagebox-known-hosts" "[${sb.host}]:${toString sb.port} ${sb.hostKey}\n";
  # Backrest adds its own sftp.args unless one is set, and restic refuses
  # sftp.args together with sftp.command: so the port goes in the URL here.
  sftpArgs = "-i ${secretPaths.storageBoxKey} -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=${knownHosts} -o StrictHostKeyChecking=yes";
  repoUri = name: "sftp://${sb.user}@${sb.host}:${toString sb.port}/restic/${name}";

  repos = lib.mapAttrsToList (name: _: {
    id = name;
    uri = repoUri name;
    env = [
      "RESTIC_PASSWORD_FILE=${
        secretPaths.${"restic" + lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (-1) name}
      }"
      "RESTIC_CACHE_DIR=/var/cache/backrest"
    ];
    flags = [ "-o 'sftp.args=${sftpArgs}'" ];
    prunePolicy.schedule.disabled = true;
    checkPolicy.schedule.disabled = true;
  }) restic.repos;

  python = pkgs.python3.withPackages (p: [ p.bcrypt ]);

  # Writes the config: repos that exist (with their restic ID) and the login.
  writeConfig = pkgs.writeShellApplication {
    name = "backrest-write-config";
    runtimeInputs = [
      pkgs.restic
      pkgs.openssh
      pkgs.jq
      python
    ];
    text = ''
      repos='[]'
      while IFS= read -r repo; do
        id=$(jq -r .id <<<"$repo")
        uri=$(jq -r .uri <<<"$repo")
        pwfile=$(jq -r '.env[0] | sub("^RESTIC_PASSWORD_FILE="; "")' <<<"$repo")
        if guid=$(RESTIC_PASSWORD_FILE=$pwfile RESTIC_CACHE_DIR=/var/cache/backrest \
          restic -r "$uri" -o sftp.args=${lib.escapeShellArg sftpArgs} cat config --json 2>/dev/null | jq -er .id); then
          repos=$(jq -c --argjson r "$repo" --arg g "$guid" '. + [$r + { guid: $g }]' <<<"$repos")
        else
          echo "repo $id not initialised yet, left out"
        fi
      done < <(jq -c '.[]' ${pkgs.writeText "backrest-repos.json" (builtins.toJSON repos)})

      hash=$(python3 -c '
      import base64, bcrypt, sys
      pw = open(sys.argv[1], "rb").read().strip()
      print(base64.b64encode(bcrypt.hashpw(pw, bcrypt.gensalt())).decode())' \
        ${secretPaths.backrestPassword})

      jq -n --argjson repos "$repos" --arg user ${lib.escapeShellArg cfg.user} --arg hash "$hash" '{
        modno: 1,
        version: 4,
        instance: "nixos-manager",
        repos: $repos,
        plans: [],
        auth: { disabled: false, users: [ { name: $user, passwordBcrypt: $hash } ] }
      }' >"$RUNTIME_DIRECTORY/config.json"
      chmod 600 "$RUNTIME_DIRECTORY/config.json"
    '';
  };
  # Backrest only indexes a repo it backed up itself, or on request (DoRepoTask
  # TASK_INDEX_SNAPSHOTS; there's no separate IndexSnapshots RPC). Our
  # backups come from restic-<name>, so ask after each run and at start:
  # `backrest-index [repo…]` (default: every repo in the running config).
  index = pkgs.writeShellApplication {
    name = "backrest-index";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      url=http://${cfg.listenAddress}:${toString cfg.port}
      # Backrest needs a moment after starting.
      for _ in $(seq 1 30); do
        curl -fs -o /dev/null "$url/" && break
        sleep 2
      done
      if [ $# -eq 0 ]; then
        mapfile -t repos < <(jq -r '.repos[].id' /run/backrest/config.json)
      else
        repos=("$@")
      fi
      for repo in "''${repos[@]}"; do
        # A repo created since Backrest started (archive's first run) isn't in
        # its config yet: a restart writes the config and indexes everything.
        if ! jq -e --arg r "$repo" 'any(.repos[]; .id == $r)' /run/backrest/config.json >/dev/null; then
          echo "backrest: $repo not configured yet, restarting backrest"
          systemctl try-restart --no-block backrest.service
          continue
        fi
        # Password via a curl config on stdin, not on the command line.
        printf 'user = "%s:%s"\n' ${lib.escapeShellArg cfg.user} "$(cat ${secretPaths.backrestPassword})" |
          curl -fsS -K - -X POST -H 'Content-Type: application/json' \
            --data "$(jq -cn --arg r "$repo" '{repoId: $r, task: "TASK_INDEX_SNAPSHOTS"}')" \
            "$url/v1.Backrest/DoRepoTask" -o /dev/null
        echo "backrest: indexing $repo"
      done
    '';
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.backup.backrest = {
    enable = lib.mkEnableOption "Backrest, a web UI for the restic repositories";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      description = "This host's Tailscale IP; Backrest is reachable on the tailnet only.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9898;
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "thijs";
    };
    passwordReference = lib.mkOption {
      type = lib.types.str;
      default = "op://Homelab/backrest/password";
    };
  };

  config = lib.mkIf cfg.enable {
    # Lodestar's Services tab. Login page answers 200/401: up.
    lodestar.links.backrest = {
      title = "Backrest";
      group = "Backups";
      description = "Browse and restore restic snapshots";
      url = "http://${cfg.listenAddress}:${toString cfg.port}";
    };

    assertions = [
      {
        assertion = restic.enable;
        message = "backup.backrest needs backup.restic.";
      }
    ];

    services.onepassword-secrets.secrets.backrestPassword = {
      reference = cfg.passwordReference;
      mode = "0400";
      owner = "root";
      services = [ "backrest" ];
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

    # On the front door as backrest.vanwaaij.com, tailnet only (the router reaches it
    # over the tailnet), behind the sign-in gate (Backrest's own login stays behind it).
    homelab.routes.backrest = {
      host = "backrest.vanwaaij.com";
      backend = "http://${cfg.listenAddress}:${toString cfg.port}";
      public = false;
      auth.gate = true;
    };

    environment.systemPackages = [ index ];

    # Index each repo right after its backup run.
    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair "restic-${name}" {
          serviceConfig.ExecStartPost = [ "-${lib.getExe index} ${name}" ];
        }
      ) restic.repos)
      {
        backrest = {
          description = "Backrest (restic web UI)";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "tailscaled.service"
            "opnix-secrets.service"
          ];
          environment = {
            BACKREST_PORT = "${cfg.listenAddress}:${toString cfg.port}";
            BACKREST_CONFIG = "/run/backrest/config.json";
            BACKREST_DATA = "/var/lib/backrest";
            BACKREST_RESTIC_COMMAND = lib.getExe pkgs.restic;
            XDG_CACHE_HOME = "/var/cache/backrest";
          };
          path = [ pkgs.openssh ];
          serviceConfig = {
            # Root: it reads the opnix secrets and restores files anywhere.
            ExecStartPre = lib.getExe writeConfig;
            ExecStart = lib.getExe pkgs.backrest;
            # "-": a failed index request doesn't fail the service.
            ExecStartPost = "-${lib.getExe index}";
            RuntimeDirectory = "backrest";
            StateDirectory = "backrest";
            CacheDirectory = "backrest";
            # The tailnet IP may not be up yet right after boot.
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };
      }
    ];
  };
}
