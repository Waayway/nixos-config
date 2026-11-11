{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Ordering for nixpkgs' tailscale-serve unit, on every server that publishes Tailscale
# Services (the router, hestia). `serve set-config` fails with "unexpected state: NoState"
# while tailscaled is still starting, e.g. right after a switch restarted it for a new
# version (hestia, 2026-11-11). Restart= recovered 10 s later, but switch-to-configuration
# had already counted the failed start (exit 4, a failed Lodestar apply). So wait for
# the backend first; Restart= stays for the logged-out case, where the wait times out.
let
  tailscale = lib.getExe config.services.tailscale.package;
  waitForRunning = pkgs.writeShellScript "tailscale-wait-running" ''
    state=unknown
    for _ in $(seq 1 60); do
      state=$(${tailscale} status --json --peers=false 2>/dev/null | ${lib.getExe pkgs.jq} -r .BackendState)
      [ "$state" = Running ] && exit 0
      sleep 1
    done
    echo "tailscaled is not Running after 60 s (state: $state)" >&2
    exit 1
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (hostPlatform.isServer && config.services.tailscale.serve.enable) {
    systemd.services.tailscale-serve = {
      after = [
        "tailscaled.service"
        "tailscaled-autoconnect.service"
      ];
      serviceConfig = {
        ExecStartPre = [ waitForRunning ];
        Restart = "on-failure";
        RestartSec = "10s";
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
  };
}
