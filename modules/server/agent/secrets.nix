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
  render = pkgs.writeShellScript "hermes-secrets-env" ''
    set -eu
    umask 077
    mkdir -p /run/hermes-secrets
    tmp=$(mktemp /run/hermes-secrets/env.XXXXXX)
    {
      printf 'DISCORD_BOT_TOKEN=%s\n' "$(cat ${secretPaths.irisDiscord})"
      printf 'OPENROUTER_API_KEY=%s\n' "$(cat ${secretPaths.irisOpenrouter})"
      printf 'HERMES_DASHBOARD_BASIC_AUTH_USERNAME=thijs\n'
      printf 'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=%s\n' "$(cat ${secretPaths.irisDashboardPassword})"
      printf 'HERMES_DASHBOARD_BASIC_AUTH_SECRET=%s\n' "$(cat ${secretPaths.irisDashboardSecret})"
    } > "$tmp"
    chown hermes:hermes "$tmp"
    mv "$tmp" ${envFile}
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.agent.enable {
    services.onepassword-secrets.secrets = {
      # Created by Thijs as an API Credential item.
      irisDiscord = secret "op://Homelab/Iris Discord Bot Token/credential";
      irisOpenrouter = secret "op://Homelab/iris-openrouter/credential";
      # Grafana service account `iris`, role Viewer (docs/agent.md).
      irisGrafana = secret "op://Homelab/iris-grafana/token";
      irisDashboardPassword = secret "op://Homelab/iris-dashboard/password";
      # HMAC key of the dashboard's sessions (survive restarts).
      irisDashboardSecret = secret "op://Homelab/iris-dashboard/secret";
    };

    systemd.services = lib.genAttrs units (_: {
      after = [ "opnix-secrets.service" ];
      wants = [ "opnix-secrets.service" ];
      serviceConfig = {
        ExecStartPre = lib.mkBefore [ "+${render}" ];
        EnvironmentFile = [ envFile ];
      };
    });
  };
}
