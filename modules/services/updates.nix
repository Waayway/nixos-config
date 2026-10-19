{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# The weekly container update (Friday 23:00): pulls the floating-tag images
# (`homelab.containers.floating`, filled in by the app modules) and restarts the
# containers whose image changed. Pinned images are never pulled here; Renovate
# proposes those as pull requests (renovate.json). Reports to Healthchecks.io
# (1Password Homelab item `healthchecks-prod-updates`, field `credential`, the check's
# ping URL): `/start`, then the plain URL on success or `/fail` with the last 100 log
# lines. The URL is a secret and is never printed.
let
  cfg = config.homelab.containers;
  secretPaths = config.services.onepassword-secrets.secretPaths;
  docker = config.virtualisation.docker.package;

  # Containers (with their unit names) that run a floating image.
  floatingContainers = lib.filterAttrs (
    _: c: lib.elem c.image cfg.floating
  ) config.virtualisation.oci-containers.containers;

  script = pkgs.writeShellScript "prod-container-update" ''
    set -uo pipefail
    export PATH=${
      lib.makeBinPath [
        docker
        pkgs.coreutils
        pkgs.curl
        pkgs.systemd
      ]
    }

    log=$(mktemp)
    trap 'rm -f "$log"' EXIT
    url=$(tr -d '[:space:]' <"$1")

    # A failing ping never fails the update; curl's stderr is dropped so the URL
    # cannot reach the journal.
    hc() { curl -fs -m 15 --retry 3 "$@" >/dev/null 2>&1 || true; }

    run() {
      local rc=0 running new
      ${lib.concatMapStrings (image: ''
        echo "pulling ${image}"
        docker pull ${lib.escapeShellArg image} || rc=1
      '') cfg.floating}
      ${lib.concatStrings (
        lib.mapAttrsToList (name: c: ''
          if running=$(docker inspect -f '{{.Image}}' ${name} 2>/dev/null); then
            new=$(docker image inspect -f '{{.Id}}' ${lib.escapeShellArg c.image} 2>/dev/null)
            if [ -n "$new" ] && [ "$running" != "$new" ]; then
              echo "restarting ${name}: image changed"
              systemctl restart ${c.serviceName}.service || rc=1
            else
              echo "${name}: image unchanged"
            fi
          else
            echo "${name}: not running, skipped"
          fi
        '') floatingContainers
      )}
      return $rc
    }

    hc "$url/start"
    if run >"$log" 2>&1; then
      cat "$log"
      hc "$url"
    else
      cat "$log"
      tail -n 100 "$log" | hc --data-binary @- "$url/fail"
      exit 1
    fi
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (cfg.enable && cfg.floating != [ ]) {
    services.onepassword-secrets.secrets.healthchecksProdUpdates = {
      reference = "op://Homelab/healthchecks-prod-updates/credential";
      mode = "0400";
      owner = "root";
    };

    systemd.services.prod-container-update = {
      description = "Pull the floating container images and restart what changed";
      after = [
        "docker.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script} ${secretPaths.healthchecksProdUpdates}";
      };
    };

    systemd.timers.prod-container-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Fri 23:00";
        Persistent = true;
      };
    };
  };
}
