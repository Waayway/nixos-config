# Split DNS for the tailnet: CoreDNS answers vanwaaij.com on tailscale0 with the
# Tailscale Service IP of each published route, and forwards everything else
# (the public records) upstream. The tailnet's nameserver setting points here.
# NixOS only.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.router;

  withAddress = lib.filterAttrs (
    name: r:
    r.tailnet.enable
    && r.tailnet.address != null
    && (cfg.tailnetServices == null || lib.elem name cfg.tailnetServices)
  ) cfg.routes;

  waitForTailnetAddress = pkgs.writeShellScript "coredns-wait-tailnet-address" ''
    for _ in $(seq 60); do
      addr=$(${lib.getExe config.services.tailscale.package} ip -4 2>/dev/null)
      if [ -n "$addr" ] && ${pkgs.iproute2}/bin/ip -4 -o addr show dev tailscale0 | grep -qF " $addr/"; then
        exit 0
      fi
      sleep 1
    done
    echo "no tailnet address on tailscale0 after 60 s" >&2
    exit 1
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
    services.coredns = {
      enable = true;
      config = ''
        vanwaaij.com:53 {
          bind tailscale0
          hosts {
        ${lib.concatMapStringsSep "\n" (r: "    ${r.tailnet.address} ${r.host}") (
          lib.attrValues withAddress
        )}
            fallthrough
          }
          forward . 1.1.1.1 9.9.9.9
          cache 30
        }
      '';
    };

    # `bind tailscale0` takes the interface's addresses once, at start: wait until the
    # node's 100.x address is on tailscale0 (up to 60 s, then fail and retry), and
    # restart with tailscaled so a new login doesn't leave it on a stale address.
    systemd.services.coredns = {
      after = [
        "tailscaled.service"
        "tailscaled-autoconnect.service"
      ];
      wants = [ "tailscaled.service" ];
      partOf = [ "tailscaled.service" ];
      serviceConfig = {
        # `+`: as root, for tailscaled's socket.
        ExecStartPre = "+${waitForTailnetAddress}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      unitConfig.StartLimitIntervalSec = 0;
    };

    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
