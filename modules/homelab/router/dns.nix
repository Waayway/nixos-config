# Split DNS for the tailnet: CoreDNS answers each published route's host on tailscale0
# with its Tailscale Service's address, looked up by name through tailscaled, and
# forwards everything else (the public records, and any other zone, for clients that
# use it as their only nameserver) upstream. The tailnet's nameserver setting points here.
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

  published = lib.filterAttrs (
    name: r: r.tailnet.enable && (cfg.tailnetServices == null || lib.elem name cfg.tailnetServices)
  ) cfg.routes;

  # One server block per published host (the most specific zone wins): the host is
  # rewritten to its Service's MagicDNS name, resolved by tailscaled, and the answer
  # rewritten back, so no Service IP lives in the repo. Other names in vanwaaij.com
  # (the public records) fall to the catch-all block below.
  serviceBlock = name: r: ''
    ${r.host}:53 {
      bind tailscale0
      rewrite stop {
        name exact ${r.host} ${cfg.servicePrefix}${name}.${cfg.tailnetDomain}
        answer auto
      }
      forward . 100.100.100.100
      cache 30
    }
  '';

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
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList serviceBlock published)}
        .:53 {
          bind tailscale0
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
