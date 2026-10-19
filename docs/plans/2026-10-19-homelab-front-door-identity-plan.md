# Homelab front door: plan for logins (Kanidm)

What this part delivers: one login for the homelab. A new small VM, **identity (111)**,
runs **Kanidm** from its official Docker image at **`id.vanwaaij.com`**, with your own
look (name, logo and a stylesheet in the repo). People sign in there once, with a
passkey or a password plus an authenticator app, and the apps trust that login:

- **Nextcloud, Immich and Jellyfin** get "Sign in with vanwaaij.com" next to their own
  login; existing accounts are linked, nothing is lost.
- **Proxmox** gets the same option next to its normal login.
- Apps **without** login support get a login screen in front of them on the router (the
  "gate"): Archipelago, the Traefik dashboard, TrueNAS and Backrest.

Lodestar switches to Kanidm in its own later plan (it needs code changes first).

Design: `2026-10-19-homelab-front-door-design.md` (section D). Technical version for the
implementing agents: `2026-10-19-homelab-front-door-identity-plan-technical.md`.

## Decisions (2026-10-20)

- **Kanidm, official Docker image**, like the other apps: current independent of NixOS
  (NixOS 26.05 only has Kanidm 1.10, which is already end-of-life; the image is 1.11).
- **Pinned version, one step at a time.** Kanidm doesn't allow skipping versions
  (1.11 → 1.12 → 1.13). Every new version arrives as its own Renovate pull request;
  merging it is the upgrade.
- **Users and access in the repo**, next to each app ("rebuild and go").
- **Your own look:** `override.css` in the repo (shown on 2026-10-20 in the demo), plus
  the name at the top and your logo.
- **Gate:** oauth2-proxy (official image) next to Traefik on the router.

## Who does what

- **Claude** does the repo work, the VMs on `pve`, the Tailscale policy, the Proxmox
  settings, connecting the apps, and testing.
- **You:**
  1. Give Claude the list of people (name, e-mail) and which apps each may use (step 1).
  2. Optionally: a logo and the colours/feel you want (step 2). Without it, Claude makes
     a first version you can adjust.
  3. Create one Tailscale Service, `id`, in the admin console (step 5).
  4. Set up your own passkey with the link Claude sends you (step 6), and pass the
     links for the other people on to them.
- Nothing gets pushed to GitHub without your OK.

## Step 1: Who gets access to what

Claude adds two things to the repo:

- **A list of people**, once: name and e-mail, and whether someone is an admin.
- **Per app, who may use it**, written next to that app's settings (Nextcloud, Immich,
  Jellyfin in their modules; Archipelago, TrueNAS, Proxmox, Traefik and Backrest in one
  file, because those don't run on NixOS).

Kanidm builds its groups from this: each app gets a group (`nextcloud-users`, …), and
the people listed become members. Giving someone access later is adding a name and
rebuilding.

**You:** send Claude the list of people and which apps each may use. Until you do, the
list contains only you.

## Step 2: Describing the identity VM

Claude writes the configuration for VM **111** (1 core, 2 GB memory):

- **Kanidm** from its official image at `id.vanwaaij.com`, with its own certificate
  (through Cloudflare, like the router's). Its data lives on the VM's own disk; a
  **daily backup** goes to TrueNAS (`/store/kanidm`), which the nightly backup to
  Hetzner already picks up.
- **Your look:** the name at the top ("vanwaaij.com" or what you prefer), your logo, and
  `override.css` from the repo.
- **Two-factor for everyone:** a password alone is never enough. Admins must use a
  passkey; everyone else may also use a password with an authenticator app.
- **No mail server.** New people and "I lost my phone" get a one-time link that Claude
  (or you) makes and you send yourself.
- **Automatic setup after every rebuild:** people, groups and app connections are
  brought in line with the repo.
- **App secrets:** for each app Kanidm makes its own secret. Claude copies it once into
  1Password with a small script; the app reads it from there. (The official image
  doesn't accept secrets from outside — only this one extra step per new app.)

And on the router:

- `id.vanwaaij.com` is passed straight through to VM 111, so even the router never sees
  passwords.
- **The gate** (oauth2-proxy, official image): a website marked "gated" sends a visitor
  without a valid login to `id.vanwaaij.com` first, and lets them in only if they're in
  that app's group. One login works for all gated sites.
- **New routes** for `truenas.vanwaaij.com` and `backrest.vanwaaij.com`, **Tailscale
  only**.

Before anything is installed, Claude checks that everything builds.

## Step 3: Trying it on the test VM (230)

VM 230 gets a test Kanidm at `id-test.vanwaaij.com` (the throwaway demo from 2026-10-20 is
removed first). Claude checks:

- Kanidm starts, the look from the repo shows, and it contains exactly the groups and
  app connections from the repo; the two-factor rule is on;
- the test page is behind the gate: without a login you're sent to the test Kanidm; a
  faked "I'm logged in" header doesn't get you through; the login can't be abused to
  send people to a site outside `vanwaaij.com`;
- sites that aren't gated still work without a login;
- a backup file appears on TrueNAS.

**You notice:** nothing.

## Step 4: The real identity VM (111)

Claude creates VM **111** from the template, starts it, waits for its certificate and
checks that `https://id.vanwaaij.com` shows your login page, from the internet and the
LAN.

## Step 5: Tailscale (you)

Create the Service `id` in the Tailscale admin console. Claude does the policy and checks
that `id.vanwaaij.com` also works over Tailscale.

## Step 6: Accounts

Claude makes a one-time link for your account; **you** open it and set up a passkey.
Claude makes the links for the other people on the list; you send them on.

## Step 7: Turning on the gate

Claude marks Archipelago, Traefik, TrueNAS and Backrest as gated. Then checks with your
account: each asks for the Kanidm login and works after it; someone outside a group gets
"access denied". Archipelago's old password goes away.

**If anything fails:** the gate goes off again for that site with one change, and
Archipelago gets its old password back.

## Step 8: Nextcloud, Immich and Jellyfin

One app at a time, Claude adds "Sign in with vanwaaij.com":

- **Nextcloud:** existing accounts are linked by username, so files and shares stay. The
  normal login stays available for the admin account (emergency way in).
- **Immich:** linked by e-mail address.
- **Jellyfin:** "Sign in" in the browser through a plugin; TV and phone apps keep their
  password or Quick Connect.

**You:** try each one once and say if it's right before the next.

## Step 9: Proxmox

Claude adds "Kanidm" as a sign-in option in Proxmox; people in `admins` become Proxmox
administrators. The normal `root` login stays as the emergency way in. **You:** try it
once.

## Step 10: Paperwork

Claude updates the docs: VM 111, the gate, which apps use Kanidm, how to add a person or
give access, how to make a recovery link, how a Kanidm upgrade goes, and where the
emergency logins are.

## When this part is done

- `id.vanwaaij.com` is the one login for the homelab, with your look and two-factor for
  everyone.
- Nextcloud, Immich, Jellyfin and Proxmox can use it; Archipelago, Traefik, TrueNAS and
  Backrest are behind it.
- Giving someone access is adding a name in the repo and rebuilding.
- Next: Lodestar on its own URL with this login.
