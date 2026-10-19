{
  lib,
  hostPlatform,
  ...
}:
# Server secrets come from the 1Password vault "Homelab" through opnix. Modules
# declare what they need next to where it's used:
#
#   services.onepassword-secrets.secrets.<name> = {
#     reference = "op://Homelab/<item>/<field>";
#     services = [ "<unit that reads it>" ];   # restarted when the value changes
#   };
#   … = config.services.onepassword-secrets.secretPaths.<name>;
#
# The one bootstrap secret per server is the token of the service account
# `opnix-homelab` (read-only on Homelab), placed once at /etc/opnix-token with
# `sudo opnix token set`. Without it opnix logs a warning and keeps the files it
# already wrote. Linux workstations need no secrets: off there. On darwin the
# Lodestar agent's signing key is the only secret (modules/lodestar/agent.nix,
# same token file). Settings below come from the spike in
# docs/plans/2026-10-12-homelab-backup-plan.md (phase 1).
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf hostPlatform.isServer {
    services.onepassword-secrets = {
      enable = true;
      tokenFile = "/etc/opnix-token";
      # The main run already restarts the units of changed secrets; the path
      # watcher only fetched everything a second time.
      systemdIntegration.changeDetection.enable = false;
      # Rotated secrets reach servers without waiting for a switch.
      systemdIntegration.polling = {
        enable = true;
        interval = "6h";
      };
    };

    systemd.services.opnix-secrets = {
      # When 1Password is unreachable, don't hold boot or a switch for minutes;
      # consumers start with the files they already have.
      serviceConfig.TimeoutStartSec = "60s";
      # opnix sets 2 starts per hour: a switch plus one manual restart hit it.
      unitConfig.StartLimitBurst = lib.mkForce 6;
    };
  };
}
