# Homelab front door: plan for the template and the router

What this part delivers: a new small VM, **router (110)**, that takes over from Main as
the front door of the homelab. Everything that is reachable from the internet today
(Nextcloud, Jellyfin, Archipelago) keeps working at the same addresses, but now goes
through the router. On top of that, the same addresses also work over Tailscale.

Kanidm (logins), Lodestar on its own URL and the new production VM come later, each
with their own plan.

Design: `2026-10-19-homelab-front-door-design.md`. The step-by-step technical version
for the implementing agents: `2026-10-19-homelab-front-door-router-plan-technical.md`.

## Who does what

- **Claude** does everything in the repo and on `pve`: creating, renumbering and
  configuring VMs, and testing.
- **You** do three things, when Claude asks:
  1. Point the WireGuard port forward (51820/udp) in UniFi at `10.0.10.118` (step 5).
  2. A few settings in the Tailscale admin console (step 4 and 6). Claude gives you
     the exact text to paste. If you'd rather not, you can give Claude an API key for
     this instead.
  3. Point the web port forward (80 and 443) in UniFi at the router `10.0.10.110`
     (step 7).
- Nothing gets pushed to GitHub without your OK.

## Step 1: A fresh base image

All new VMs are copies of template 9000. That template is from 13 October and uses
NixOS packages from May. Claude:

- updates the NixOS packages to the current 26.05 release (this is also the regular
  security update for the servers, which they pick up on their next update);
- checks that every machine in the repo still builds with it;
- builds a new template image, replaces template 9000 with it (the old image is kept
  as a backup file on `pve`) and puts it on the fast local disk instead of the nearly
  full `store-lvm`;
- makes the first copy, the test VM **230**, and checks that it starts and that Claude
  can log in.

**You notice:** nothing.

## Step 2: Describing the router

Claude writes the router's configuration in the repo. In plain terms it contains:

- **The list of websites** it serves, with for each one: its address
  (`jellyfin.vanwaaij.com`), where the app actually runs (`10.0.10.120`), and
  whether it is reachable from the internet, over Tailscale, or both. At first:
  Nextcloud, Jellyfin, Archipelago (with its current username and password) and the
  Traefik dashboard (Tailscale only). Immich and BlueMap are left out because they
  are switched off today.
- **Traefik**, the program that receives the visitors and passes them on to the right
  app, with one certificate for all `*.vanwaaij.com` addresses. The certificate is
  requested through Cloudflare, with the same Cloudflare key Main uses now. Claude
  moves that key, and the Archipelago password, into 1Password, so they no longer
  sit in plain files.
- **A marker for Tailscale traffic.** Visitors who come in over Tailscale get a
  hidden label on their request; anyone from the internet who tries to fake that
  label has it removed. Lodestar will use this later to only allow actions over
  Tailscale.
- **Tailscale on the router:** each website also becomes a Tailscale Service
  (`svc:jellyfin`, …), and the router offers your home network (`10.0.10.0/24`) and
  an exit node to your tailnet.
- **A small DNS server** on the router. When you're on Tailscale, it makes
  `jellyfin.vanwaaij.com` point to the Tailscale route instead of your public IP, so
  the same address works both ways.
- **Two machine descriptions:** `router` (110) and `router-test` (230). The test
  version uses a test certificate and only one test website, a small "echo" page that
  shows exactly what reached it, which is how the marker is checked.

Before anything is installed, Claude checks that the configuration produces exactly
this (the right websites, ports and marker) and that all other machines still build.

**You notice:** nothing.

## Step 3: Trying it on the test VM (230)

Claude installs the test configuration on VM 230 and checks, from the LAN:

- the echo page answers, and a faked Tailscale marker from outside is removed;
- an address that isn't on the list gives "not found", not some other app;
- `http://` is redirected to `https://`;
- Jellyfin answers through it, and Archipelago asks for its password.

## Step 4: Tailscale settings, round 1 (you)

Claude gives you a short piece of text for the Tailscale admin console that:

- allows the router to offer the home network, the exit node and Services;
- lets your own devices use those;
- creates one test Service for the echo page.

Then Claude checks over Tailscale that the echo page is reachable at its normal
address and that the marker is there.

## Step 5: Moving the old VPN VM out of the way

The router needs number 110, which the old WireGuard VM uses now. Claude:

- shuts the WireGuard VM down, renumbers it to **118** and changes its address to
  `10.0.10.118`;
- starts it again and checks that it answers on the new address.

**You:** point the WireGuard port forward (51820/udp) in UniFi at `10.0.10.118`, and
check that a VPN client connects. The VPN is down for a few minutes during this step;
tell the people who use it, or pick a quiet moment.

## Step 6: The real router (110)

Claude creates VM **110** from the template (2 cores, 2 GB memory), starts it with the
router configuration and waits for the real certificate.

**You:** create the real Tailscale Services (`nextcloud`, `jellyfin`, `archipelago`,
`traefik`) and switch on split DNS for `vanwaaij.com` → the router. Claude gives you
the exact steps.

Claude then checks every website through the router, from the LAN and over Tailscale.
Main keeps serving the internet during all of this.

## Step 7: Switching over

- Claude makes Nextcloud on Main reachable for the router directly, and tells
  Nextcloud to trust the router (so it sees the visitors' real addresses and keeps
  using `https`). The original files are kept as a copy.
- **You:** point the web port forward (80 and 443) in UniFi at `10.0.10.110`.
- Claude checks from outside your home that Nextcloud, Jellyfin and Archipelago work
  with the new certificate, and checks Nextcloud specifically: logging in, calendar
  and contacts sync, and no warnings in its admin page.
- Then Claude stops the old Traefik on Main (Nextcloud itself keeps running there).

**If anything fails:** you point the port forward back at `10.0.10.100`, Claude starts
Main's Traefik again and restores the copied files. Nothing on Main is deleted.

## Step 8: Paperwork

Claude updates the docs: the homelab inventory (router, VPN at 118, Main no longer the
front door, Jenkins "moves later" instead of "retired"), the machine list in
AGENTS.md, and the Tailscale policy notes.

## When this part is done

- The internet reaches your sites through the router; Main only runs Nextcloud.
- On Tailscale, the same addresses go over Tailscale.
- Adding a website later is one entry in the repo.
- VM 230 stays around for testing Kanidm next.
