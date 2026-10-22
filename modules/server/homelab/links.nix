# Lodestar Services tab: the services on machines this flake doesn't manage yet
# (Rocky VMs, Proxmox, TrueNAS). Declared once, on the host that runs the Lodestar
# server. When a VM moves to NixOS, its entries move into that service's module
# (`lodestar.links.<id>` next to the service, `host` dropped). Traefik's link lives in
# the router module (modules/server/homelab/router/).
#
# Checks run from nixos-manager. Main's Traefik (80/443) is not reachable from the
# LAN, by public name or by 10.0.10.100, so services behind it are probed on their
# backend where one is reachable (`check.url`).
{ config, lib, ... }:
{
  config = lib.mkIf (config.services.lodestar-server.enable or false) {
    lodestar.links = {
      archipelago = {
        title = "Archipelago";
        group = "Games";
        description = "Multiworld randomizer";
        url = "https://ap.vanwaaij.com";
        host = "archipelago";
        check.url = "http://10.0.10.201:8080";
      };
      proxmox = {
        title = "Proxmox";
        group = "Infrastructure";
        description = "Hypervisor";
        icon = "proxmox";
        url = "https://pve.tail41ca60.ts.net:8006";
        host = "pve";
      };
      truenas = {
        title = "TrueNAS";
        group = "Infrastructure";
        description = "Storage: NFS, SMB and iSCSI";
        icon = "truenas";
        url = "https://10.0.10.130";
        host = "truenas";
        check.insecureTls = true;
      };
    };
  };
}
