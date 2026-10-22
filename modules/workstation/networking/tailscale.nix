{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Linux workstations are reached through Tailscale SSH (no sshd). `extraUpFlags`
# only reaches `tailscaled-autoconnect`, which exists only with an auth key
# (servers), so the SSH server is switched on here. `tailscale set --ssh` also
# works on a logged-out node: it stores the pref for the next login.
# Never fails a switch or boot: it retries while tailscaled starts, then logs
# and exits 0.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!hostPlatform.isServer) {
    systemd.services.tailscale-ssh = {
      description = "Turn on the Tailscale SSH server";
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for _ in $(${pkgs.coreutils}/bin/seq 30); do
          if ${config.services.tailscale.package}/bin/tailscale set --ssh; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "tailscale-ssh: tailscaled did not answer within 30s; Tailscale SSH not set" >&2
        exit 0
      '';
    };
  };
}
