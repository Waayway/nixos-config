# Lodestar Services tab: the services on machines this flake doesn't manage yet
# (Rocky VMs, Proxmox, TrueNAS). Declared once, on the host that runs the Lodestar
# server. When a VM moves to NixOS, its entries move into that service's module
# (`lodestar.links.<id>` next to the service, `host` dropped).
#
# Checks run from nixos-manager. Main's Traefik (80/443) is not reachable from the
# LAN, by public name or by 10.0.10.100, so services behind it are probed on their
# backend where one is reachable (`check.url`).
{ config, lib, ... }:
{
  config = lib.mkIf (config.services.lodestar-server.enable or false) {
    lodestar.links = {
      nextcloud = {
        title = "Nextcloud";
        group = "Apps";
        description = "Files, contacts and documents";
        icon = "nextcloud";
        url = "https://nextcloud.vanwaaij.com";
        host = "main";
        # Only reachable through Main's Traefik, which the LAN can't reach.
        check.enable = false;
      };
      jellyfin = {
        title = "Jellyfin";
        group = "Media";
        description = "Media server";
        icon = "jellyfin";
        url = "https://jellyfin.vanwaaij.com";
        host = "media";
        check.url = "http://10.0.10.120:8096";
      };
      archipelago = {
        title = "Archipelago";
        group = "Games";
        description = "Multiworld randomizer";
        url = "https://ap.vanwaaij.com";
        host = "archipelago";
        check.url = "http://10.0.10.201:8080";
      };
      traefik = {
        title = "Traefik";
        group = "Infrastructure";
        description = "Ingress dashboard on Main";
        icon = "traefikproxy";
        url = "https://traefik.tail41ca60.ts.net";
        host = "main";
        # Its certificate doesn't verify from nixos-manager.
        check.insecureTls = true;
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
