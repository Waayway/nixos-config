{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Backrest (web UI for restic) over the restic repositories of
# modules/backup/restic.nix: browse snapshots, restore files. Read-only in
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

    systemd.services.backrest = {
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
        RuntimeDirectory = "backrest";
        StateDirectory = "backrest";
        CacheDirectory = "backrest";
        # The tailnet IP may not be up yet right after boot.
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
