# Homelab dashboard: design

A dashboard of every application the homelab hosts, with its URL and a live state, built
from this flake. It is the **Services** tab of Lodestar: the feature (options, checker,
UI) is designed in `~/lodestar/docs/plans/2026-10-13-service-links-design.md`; this file
covers the declarations here.

Status: approved in conversation 2026-10-13.

## Decisions

- **Inside Lodestar, not a separate app** (considered: a Nix-rendered static page with the
  Lodestar theme, and Homepage with Lodestar CSS). One URL and one login (tailnet), the
  Lodestar look by construction, and the service's host state comes for free.
- **Declared as code, follows git.** Links are Nix data; a change goes `unstable` →
  promote → `stable` → applied on nixos-manager, which rewrites
  `/etc/lodestar-server/links.json` and restarts the server.
- **Live state:** an HTTP check per link every 60 s from nixos-manager, plus the online
  state of the host it runs on when that host is in the fleet.

## Where links are declared

`lodestar.links.<id>` (option from `inputs.lodestar`, already imported on every host via
`nixosModules.default` / `darwinModules.default` in `lib/mkSystem.nix` and
`lib/mkDarwin.nix`). Ids are unique across the whole flake.

1. **Next to the service**, inside the module's own `mkIf`, so the link exists exactly
   when the service does. `host` stays `null` (the declaring machine).
   - `modules/backup/backrest.nix`: `backrest`, group *Backups*,
     `http://${cfg.listenAddress}:${toString cfg.port}`, no icon (Simple Icons has no restic mark; the card shows "B").
   - `modules/lodestar/server.nix`: `lodestar`, group *Infrastructure*,
     `http://${listenAddress}:${toString listenPort}`; `check.enable = false` (it is the
     page you are looking at).
   - Every future NixOS service module (Nextcloud, Jellyfin, … as the VMs move) does the
     same.
2. **By hand, for machines not managed by this flake yet:** a new
   `modules/homelab/links.nix`, applied only where the Lodestar server runs:

   ```nix
   { config, lib, ... }:
   {
     config = lib.mkIf (config.services.lodestar-server.enable or false) {
       lodestar.links = {
         nextcloud = { title = "Nextcloud"; url = "https://nextcloud.vanwaaij.com"; host = "main"; group = "Apps"; icon = "nextcloud";
                       check.url = "https://10.0.10.100"; /* hairpin NAT, see below */ };
         jellyfin = { title = "Jellyfin"; url = "https://jellyfin.vanwaaij.com"; host = "media"; group = "Media"; icon = "jellyfin"; };
         archipelago = { title = "Archipelago"; url = "https://ap.vanwaaij.com"; host = "archipelago"; group = "Games"; };
         traefik = { title = "Traefik"; url = "https://traefik.tail41ca60.ts.net"; host = "main"; group = "Infrastructure"; icon = "traefikproxy"; };
         proxmox = { title = "Proxmox"; url = "https://pve.tail41ca60.ts.net:8006"; host = "pve"; group = "Infrastructure"; icon = "proxmox"; };
         truenas = { title = "TrueNAS"; url = "https://10.0.10.130"; host = "truenas"; group = "Infrastructure"; icon = "truenas"; check.insecureTls = true; };
       };
     };
   }
   ```

   Exact URLs and check overrides are confirmed against the live services during
   implementation (`curl -sI` from nixos-manager). Dead services (Immich, BlueMap) are not
   listed until they run again. When a VM moves to NixOS, its entries move from this file
   into that service's module, and `host` is dropped.

   This keeps to the repo rule: the module is imported everywhere and turns itself off by
   condition. `links.nix` is a plain module (no enable option): it has nothing to enable
   beyond "this host runs the Lodestar server".

## Server wiring

`modules/lodestar/server.nix` adds, next to `hosts`:

```nix
links = inputs.lodestar.lib.linksFrom {
  inherit (inputs.self) nixosConfigurations darwinConfigurations;
};
```

No host file changes. No firewall changes: probes are outbound from nixos-manager, which
reaches the LAN (10.0.10.0/24) and the tailnet.

## Things to watch

- **Hairpin NAT:** public names served by Traefik on Main may not resolve back into the
  LAN from nixos-manager (Main itself needs an `extra_hosts` workaround for Nextcloud).
  Probe the LAN address with `check.url` where needed; a cert mismatch on an IP then needs
  `check.insecureTls` or probing plain HTTP. Decide per link during implementation.
- **Self-signed UIs** (TrueNAS on its LAN IP): `check.insecureTls = true`.
- **Evaluation cost:** `linksFrom` forces `lodestar.links` on every configuration when
  nixos-manager evaluates, like `hostsFrom` already does; no new cross-host dependency
  shape.

## Rollout

1. Lodestar implements the feature (its own plan), released on its main branch.
2. Here: `nix flake update lodestar`, `modules/homelab/links.nix`, the links in
   `backrest.nix` and `lodestar/server.nix`, the `linksFrom` wiring; commit on `unstable`.
3. Verify: all five hosts evaluate; on nixos-manager
   `nix eval .#nixosConfigurations.nixos-manager.config.services.lodestar-server.links --json`
   lists the expected ids with `host` filled in; atlas/apollo/hermes/hephaestus still
   evaluate with no links.
4. Promote to `stable`, apply nixos-manager through Lodestar, open the Services tab:
   every link up (or down for a stated reason that matches reality).
5. `docs/homelab.md`: a short "Dashboard" section (where links live, how to add one).
