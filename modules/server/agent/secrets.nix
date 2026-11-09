{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# iris's secrets, from 1Password Homelab through opnix (modules/server/secrets/opnix.nix).
# Upstream's `environmentFiles` are copied into $HERMES_HOME/.env at activation, which
# runs before opnix fetches anything (first boot: no files yet; a rotated token: the old
# one until the next switch). So the units get them at start instead: a root
# ExecStartPre renders /run/hermes-secrets/env from the secret files, and systemd reads
# it as EnvironmentFile just before ExecStart. opnix restarts both units when a value
# changes. The Grafana token isn't in it: the MCP wrapper (hermes.nix) reads its file.
let
  secretPaths = config.services.onepassword-secrets.secretPaths;
  units = [
    "hermes-agent"
    "hermes-backend"
  ];
  secret = reference: {
    inherit reference;
    owner = "hermes";
    group = "hermes";
    mode = "0400";
    services = units;
  };
  envFile = "/run/hermes-secrets/env";
  # `need NAME file`: one NAME=value line, or stop naming what's missing. Values are
  # restricted to characters systemd's env-file parser leaves alone (no quotes,
  # backslashes or spaces): tokens and keys are, and the dashboard password is
  # generated letters and digits (docs/agent.md).
  renderText = ''
    set -eu
    umask 077
    need() {
      if ! [ -s "$2" ]; then
        echo "hermes-secrets-env: $1: $2 is missing or empty (opnix token? item name?)" >&2
        exit 1
      fi
      v=$(cat "$2")
      case "$v" in
        *[!A-Za-z0-9._~+/=:-]*)
          echo "hermes-secrets-env: $1 has characters an env file would change" >&2
          exit 1
          ;;
      esac
      printf '%s=%s\n' "$1" "$v"
    }
    mkdir -p /run/hermes-secrets
    tmp=$(mktemp /run/hermes-secrets/env.XXXXXX)
    {
      need DISCORD_BOT_TOKEN ${secretPaths.irisDiscord}
      echo HERMES_DASHBOARD_BASIC_AUTH_USERNAME=thijs
      need HERMES_DASHBOARD_BASIC_AUTH_PASSWORD ${secretPaths.irisDashboardPassword}
      need HERMES_DASHBOARD_BASIC_AUTH_SECRET ${secretPaths.irisDashboardSecret}
    } > "$tmp"
    chown hermes:hermes "$tmp"
    mv "$tmp" ${envFile}
  '';
  render = pkgs.writeShellScript "hermes-secrets-env" renderText;
in
lib.optionalAttrs hostPlatform.isLinux {
  # The render script's text, for tests/agent.nix (reading the built script would need
  # a Linux builder at evaluation).
  options.homelab.agent.secretsEnvScript = lib.mkOption {
    type = lib.types.str;
    internal = true;
    readOnly = true;
    default = renderText;
  };

  config = lib.mkIf config.homelab.agent.enable {
    services.onepassword-secrets.secrets = {
      # Created by Thijs as an API Credential item.
      irisDiscord = secret "op://Homelab/Iris Discord Bot Token/credential";
      # Grafana service account `iris`, role Viewer (docs/agent.md).
      irisGrafana = secret "op://Homelab/iris-grafana/token";
      irisDashboardPassword = secret "op://Homelab/iris-dashboard/password";
      # HMAC key of the dashboard's sessions (survive restarts).
      irisDashboardSecret = secret "op://Homelab/iris-dashboard/secret";
    };

    systemd.services = lib.genAttrs units (_: {
      # Hermes reads .env and config.yaml only at start, and upstream's activation
      # rewrites them without restarting anything: restart when they change in Nix.
      restartTriggers = [
        (builtins.toJSON config.services.hermes-agent.environment)
        (builtins.toJSON config.services.hermes-agent.settings)
      ];
      after = [ "opnix-secrets.service" ];
      wants = [ "opnix-secrets.service" ];
      serviceConfig = {
        ExecStartPre = lib.mkBefore [ "+${render}" ];
        # `-`: systemd loads it for ExecStartPre too, before the render has written
        # it (/run is empty after boot); ExecStart then reads the fresh file.
        EnvironmentFile = [ "-${envFile}" ];
      };
    });
  };
}
