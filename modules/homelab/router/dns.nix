# Split DNS for the tailnet: CoreDNS answers vanwaaij.com on tailscale0 with the
# Tailscale Service IP of each published route, and forwards everything else
# (the public records) upstream. The tailnet's nameserver setting points here.
# NixOS only.
{
  config,
  lib,
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

    # `bind tailscale0` fails until the interface exists.
    systemd.services.coredns = {
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      serviceConfig = {
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
