# Homelab front door: plan for the production VM (100)

What this part delivers: one new NixOS VM, **prod (100)**, running **Nextcloud, Jellyfin
and Immich**, with their files read straight from TrueNAS. When it's done, the
internet goes to the router, the router sends people to VM 100, and old Main and media
are switched off (deleted later, as the very last step).

This replaces the last step of the router plan ("switch over to Main"): the internet
moves to the router only once VM 100 works.

Design: `2026-10-19-homelab-front-door-design.md` (section C). Technical version:
`2026-10-19-homelab-front-door-production-plan-technical.md`.

## The rules for this move (your decisions)

- **Files stay on TrueNAS.** Every VM mounts TrueNAS the same way: **`/store`** and
  **`/archive`**. Nothing big is copied.
- **Only the databases move at the last minute.** Until then VM 100 runs on copies.
- **Everything is tested over Tailscale first.** On Tailscale, `nextcloud.vanwaaij.com`
  and friends already go to VM 100; the internet keeps going to Main and media until
  everything works.
- **During the final switch, visitors see a "we're working on it" page** instead of an
  error.
- Logging in with Kanidm comes later (the identity plan); for now each app keeps its own
  accounts.

## Who does what

- **Claude:** the repo, VM 100, all copying and testing, the final switch.
- **You:**
  1. Give old Main a new address, **`10.0.10.108`**, and move the web port forward
     (80/443) along to `.108` at the same moment (step 2).
  2. Create two Tailscale Services (step 5): `immich` and `office` (for Collabora,
     Nextcloud's document editor).
  3. Test the apps on Tailscale yourself, on your phone too (step 6).
  4. At the final switch, move the web port forward to the router `10.0.10.110` (step 7).
- Nothing gets pushed to GitHub without your OK.

## Step 1: TrueNAS on every VM

Claude adds one setting that mounts TrueNAS on a VM:

- **`/store`** = TrueNAS `store/internal` (Nextcloud files, Jellyfin settings, Immich
  photos, database dumps);
- **`/archive`** = TrueNAS `archive/shares` (the Jellyfin library and the other shares).
  TrueNAS doesn't share that folder over NFS yet; Claude adds that share to the TrueNAS
  settings in the repo.

**You notice:** nothing.

## Step 2: Making room for VM 100

- Claude shuts nothing down. **You** change Main's address from `.100` to **`.108`**
  (in its network settings or its DHCP reservation, whatever you used) and move the web
  port forward to `.108` right after. Nextcloud, Jellyfin and Archipelago are briefly
  unreachable from the internet while you do this.
- Claude checks that Main works on `.108`, then updates the router's list (Nextcloud's
  address) and renumbers the old VM in Proxmox from 100 to **108**. (Renumbering needs
  the VM off for a minute; Claude does that at a quiet moment and tells you first.)

## Step 3: Describing VM 100

Claude writes the configuration for VM **100** (6 cores, 16 GB memory, 64 GB disk). The
VM itself is NixOS; **the apps and their databases run from the makers' official Docker
images**, described in the repo:

- **Nextcloud** 32 with its own MariaDB database, Redis and **Collabora** (the document
  editor, at `office.vanwaaij.com`). Its files are the same files on
  `/store/nextcloud/data`, at the same place inside the container as on Main today.
- **Jellyfin** with its library from `/archive`, and its settings, users and watch history
  from a copy of `/store/jellyfin`.
- **Immich**, starting fresh. The photos already on TrueNAS are added as a library it
  reads from, so nothing is lost; albums and faces are rebuilt.
- **Databases** live on VM 100's own disk; every night a copy goes to `/store/db-dumps`,
  which the existing backup to Hetzner already picks up.
- On the router: a **"we're working on it" page** that any website can be switched to
  with one setting. (Done.)
- The router finds the Tailscale address of each app by its name, so no addresses have to
  be copied into the repo anymore.

**Staying up to date:**

- **Every Friday night** VM 100 fetches the newest versions within each app's current
  line (Nextcloud 32.x, Jellyfin 10.11.x, Immich 2.x) and restarts what changed. If that
  goes wrong, Healthchecks.io mails you.
- **Bigger steps** (a new major version of an app, any database update) are never taken
  automatically. A bot on GitHub (Renovate) opens a pull request for each one, with the
  release notes; you get a notification, and merging it is the upgrade. **You:** install
  the Renovate app on the GitHub repo once (Claude tells you when).

Before anything is installed, Claude checks that everything builds.

## Step 4: VM 100 comes up

Claude creates VM 100, installs the configuration and fills it with **copies**:

- a fresh copy of Nextcloud's database, loaded into the new MariaDB (Main keeps running
  on the original);
- a copy of Jellyfin's settings folder (Jellyfin on media keeps running on the original).

Two Nextclouds on the same files is fine for reading, but Claude switches off the new
one's background jobs until the final switch, so it doesn't change files behind Main's
back.

Jellyfin on VM 100 runs without the graphics card for now (the card stays in media until
the final switch), so video conversion is slower during testing.

## Step 5: Tailscale points at VM 100 (you + Claude)

**You:** create the Services **`immich`** and **`office`**. Claude does the policy and
points `nextcloud`, `jellyfin`, `immich` and `office` on Tailscale at VM 100. From now
on, on Tailscale you see the new setup; from the internet, the old one.

## Step 6: Testing on Tailscale

Claude checks, and **you** try on your laptop and phone, over Tailscale:

- **Nextcloud:** log in, see your files, open a document in Collabora, calendar and
  contacts sync on your phone. (Changes you make here are on the copy of the database
  and disappear at the switch; uploaded files would stay on TrueNAS, so test with
  throwaway files and delete them again.)
- **Jellyfin:** log in, your libraries and watch progress are there, a film plays.
- **Immich:** create your account, the existing photos show up, the phone app connects.

Anything that doesn't work gets fixed and tested again. **The final switch only happens
after you say it all works.**

## Step 7: The final switch

At a moment you pick:

1. The router puts up the **"we're working on it" page** for Nextcloud, Jellyfin and
   Immich. **You** move the web port forward to the router `10.0.10.110`. From now on
   visitors see the page.
2. Claude stops Nextcloud on Main and Jellyfin on media.
3. **The databases move:** a fresh copy of Nextcloud's database goes to VM 100 (and gets
   upgraded to the newer version), and Jellyfin's settings are copied one last time.
4. The graphics card moves from media to VM 100.
5. Claude switches the new Nextcloud's background jobs on, takes the page down, and the
   internet goes to VM 100.
6. Claude checks everything from outside your home: Nextcloud (login, calendar, contacts,
   Collabora), Jellyfin (a film plays, with the graphics card), Immich, Archipelago.

**If anything fails:** the page stays up, the port forward goes back to Main (`.108`),
and Main and media are started again with their original databases, which weren't
changed. Nothing on Main or media is deleted.

## Step 8: Afterwards

- Main (108) and media (120) stay **shut down** (not deleted).
- Claude updates the docs: the inventory, where each app lives, how to restore a
  database dump.
- Next: logging in with Kanidm (the identity plan), then Lodestar.
- The very last step, at some later moment: deleting Main and media.
