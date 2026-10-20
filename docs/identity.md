# Identity: Kanidm and the sign-in gate

How people sign in to the homelab, and how to change who can. Design:
`docs/plans/2026-10-19-homelab-front-door-design.md` (section D); inventory and open
findings: `docs/homelab.md` ("111 identity", "What could be better").

## What runs

- **Kanidm** on VM 111 (`identity`, `10.0.10.111`) at `https://id.vanwaaij.com`, from the
  official image (`modules/identity/kanidm.nix`). People sign in with a passkey. The
  router passes `id.vanwaaij.com` through to it without terminating TLS (Tailscale
  Service `id`; the VM gets its own Let's Encrypt certificate).
- **The sign-in gate**: oauth2-proxy on the router (`modules/homelab/router/gate.nix`),
  a Kanidm client shown as "Services" at `auth.vanwaaij.com` (Tailscale Service `auth`).
  A route with `auth.gate = true` (`modules/homelab/routes.nix`) asks it through
  Traefik's forwardAuth; without a session you are sent to Kanidm. One sign-in covers
  every gated site (cookie on `.vanwaaij.com`). The session is refreshed against Kanidm
  every 10 minutes (`--cookie-refresh`; the tokens live 15). If Kanidm or the proxy is
  down, new sign-ins fail closed (an existing session works until its next refresh);
  the other sites are unaffected.
- **Who may use what** is declared in Nix, not clicked together in Kanidm:
  - People: `modules/identity/people.nix` (`thijs` is admin, `arie`).
  - Apps with their own login: `homelab.access.<app>` in the app's module
    (`nextcloud`, `immich`, `jellyfin`: thijs and arie).
  - Apps without a module here: `homelab.identity.extraAccess` in
    `modules/identity/access.nix` (`archipelago`, `traefik`, `truenas`, `backrest` behind
    the gate, and `proxmox`; thijs only).
  - The option type is `lib/accessType.nix`: `members`, `oidc` (OAuth2 client:
    redirect URLs, icon, scopes, `usernames`, `preferShortUsername`) and `gate`.
  - Kanidm's provisioning (kanidm-provision) runs on every switch of VM 111 and makes
    Kanidm match: a group `<app>-users` and an OAuth2 client per app. Group membership is
    **overwritten** from Nix. Removing an app or member does not delete the client or
    group (`--no-auto-remove`); delete those by hand in Kanidm.

| App | Sign-in | Notes |
|---|---|---|
| Nextcloud | Kanidm (OIDC, `user_oidc`) | `usernames` maps thijs to the old account `Waayway`, arie to `Arie` |
| Immich | Kanidm (OIDC) | accounts are not created by login; email links the login to the account |
| Jellyfin | Kanidm (SSO-Auth plugin, provider `kanidm`) | a first login creates the user; people with `admin = true` in `people.nix` become Jellyfin administrators (plugin `AdminRoles`), and everyone gets all libraries |
| Lodestar | Kanidm (OIDC, its own login at `lodestar.vanwaaij.com`) | `lodestar-users` may log in as readers; `admins` act (and must also be in `lodestar-users`: the scope map exists only for that group); see `docs/lodestar.md` |
| Proxmox | Kanidm (realm `kanidm`, OpenID) | users are created by hand, see below |
| Archipelago, Traefik dashboard, TrueNAS, Backrest | the gate | TrueNAS still has its own login behind it |

## Give someone access

1. New person: add them to `modules/identity/people.nix` (name, displayName, email), on
   every host (the value is shared; the file is imported everywhere).
2. Add the name to `members` of each app they should have (see above).
3. Format, commit, push `unstable`, promote to `stable`, apply to `identity` and the
   hosts that changed (Lodestar, `docs/lodestar.md`). Provisioning creates the person
   and groups in Kanidm.
4. Make an enrolment link and send it to them (valid 24 hours, single use, the person
   registers a passkey):

   ```sh
   scripts/kanidm-reset-link.sh <person>      # --ttl <seconds> to change the expiry
   ```

   It runs from atlas over SSH (`pve` jump, then VM 111) and prints a link on
   `id.vanwaaij.com`. Use this script rather than the `kanidm` CLI: the CLI builds the
   link from the address it talks to (`https://10.0.10.111:8443/...`) and a passkey
   can't be registered for that domain. The same script gives a **new link when someone
   loses their passkey** (an older link stays valid until it expires).
5. Per app, once:
   - **Immich**: create the account first (Administration, Users) with the same email
     as in `people.nix` (autoRegister is off). Arie: `arie@vanwaaij.com`. Until it
     exists the login says no account. Phone app: it signs in through the same button.
   - **Jellyfin**: nothing; the first SSO login creates the user (an administrator only if the person has `admin = true`). A person whose short name equals an existing Jellyfin user logs into that user.
   - **Nextcloud**: nothing for a name that exists; `usernames` links a person to an
     existing account, otherwise a new account is created at first login.
   - **Proxmox**: Kanidm only decides who can get a token; Proxmox has no group sync
     and does not create users (`autocreate 0`). Add the person to `proxmox` members,
     then on pve: `pveum user add <name>@kanidm` and
     `pveum acl modify / --users <name>@kanidm --roles <Role>`. User names are the
     short ones (`thijs@kanidm`, `preferShortUsername`).
6. Remove someone: take them out of `members` and apply (they lose the group, so no new
   token and no gate access; an existing gate session ends at its next refresh, within
   about 10 minutes). Existing app sessions and accounts stay; remove those in
   the app too.

## Add a new app

1. In the app's module, declare `homelab.access.<app>` (`members`, `oidc` with the
   redirect URLs from the app's documentation, a `scopes` list if the default four are
   too many, and `icon`: SVG under `modules/identity/branding/icons/`). For an app
   without a module here use `homelab.identity.extraAccess.<app>` in
   `modules/identity/access.nix`. For a gate-only app, set `gate = true` and
   `auth.gate = true` on its route, no `oidc`.
2. Apply to VM 111. The client now exists; Kanidm generates its secret (the official
   image can't take a provisioned one).
3. Copy the secret into 1Password (Homelab item `kanidm-oauth2-<app>`, field
   `credential`) from atlas, Touch ID needed:

   ```sh
   scripts/kanidm-oauth2-secret.sh <app>      # --test for the test Kanidm on VM 230
   ```

   The secret goes SSH stdout, shell variable, 1Password; it is never printed, in argv
   or on disk. Re-run it after a client is recreated or its secret reset.
4. Configure the app with: issuer `https://id.vanwaaij.com/oauth2/openid/<app>`
   (discovery: `.../.well-known/openid-configuration`), client id `<app>`, the secret.
   Kanidm signs with ES256 and enforces PKCE.
5. A backend on the tailnet must reach `svc:id`: the Tailscale policy has a grant
   `tag:prod` to `svc:id` on tcp:443 (`docs/lodestar.md`). A new host that runs an
   OIDC app needs the same.

Where the secret lives, per consumer (so you can rotate it):

| Consumer | Secret |
|---|---|
| gate (oauth2-proxy) | opnix file from `kanidm-oauth2-oauth2-proxy` (plus `oauth2-proxy-cookie`) |
| Nextcloud | set once with `occ` (`user_oidc` provider `vanwaaij.com`) |
| Immich | copy in the Immich database, `system_metadata`, key `oauth` (admin UI: Administration, Settings, Authentication) |
| Jellyfin | `plugins/configurations/SSO-Auth.xml` in Jellyfin's state |
| Lodestar | opnix file from `kanidm-oauth2-lodestar` on nixos-manager, read at each login |
| Proxmox | realm `kanidm` in `/etc/pve/domains.cfg` |

Only the gate and Lodestar read 1Password at runtime. The other four hold their own copy, so after
resetting a client's secret update each by hand. Immich's and Jellyfin's copies are
also in their backups and DB dumps. Immich's OAuth settings were written to the database
directly (no admin token without the user's password); the admin UI shows and edits
them. After changing the Jellyfin plugin config, check it in the plugin page.

## Emergency logins

Single sign-on must never be the only way in:

| System | Way in without Kanidm |
|---|---|
| Nextcloud | local admin login |
| Jellyfin | password of the local user |
| Immich | password login (still enabled) |
| Proxmox | `root@pam` |
| Kanidm itself | `admin` / `idm_admin` via `recover-account` on VM 111 |
| Gated tools (Traefik, Backrest, Archipelago) | SSH to the VM or tailnet to the backend (Archipelago also answers on `10.0.10.201:8080`, finding 31); TrueNAS has its own login and its UI answers on `https://10.0.10.130` from the LAN (or the subnet route) |

Recover a Kanidm account (prints a new password; run on VM 111, `ssh -J pve
identity@10.0.10.111` with `~/.ssh/proxmox_vms_rsa`):

```sh
docker exec kanidm /sbin/kanidmd scripting recover-account -c /data/server.toml admin
```

Provisioning does this for `idm_admin` on every run, so no admin password is stored.
If the gate or Kanidm is broken, do not just set `auth.gate = false`: that leaves the
site without any login. Archipelago: restore `basicAuth.usersFile` from the 1Password
item `archipelago-basic-auth` (see the comment in `modules/homelab/routes.nix`), then
apply to the router. Backrest, Traefik and TrueNAS have their own access (SSH, tailnet
backend, LAN UI).

## Upgrades

- Kanidm images are pinned by digest in `modules/identity/kanidm.nix` (`serverImage`,
  `toolsImage`, the same version). Kanidm supports **one minor release at a time**: never
  skip. Before each: read the release notes, take a backup (below), run
  `kanidmd domain upgrade-check` in the container, then bump both images and apply.
  A database migrated by a newer Kanidm cannot go back; roll back from the backup.
- oauth2-proxy is pinned in `modules/homelab/router/gate.nix`. After upgrading, check
  one gated site signs in.
- Renovate raises PRs for the images; merge them one minor at a time.

## Backup and restore

- Kanidm writes an online backup daily at 22:00, 7 kept, to TrueNAS `store/authentication`
  (NFS export for `10.0.10.111` only, mounted at `/var/lib/identity/backup`). The files
  contain password hashes and OAuth2 secrets, so the dataset is private to this VM
  (root squashed, owner `65534:65534`, mode `0700`, set by hand; finding 40). It is part
  of the nightly restic backups to the Storage Box.
- Because of `RequiresMountsFor`, Kanidm does not start if TrueNAS is down at boot
  (finding 41).
- After an ACME certificate reload the next backup may run a day late (finding 47).
- Restore (not rehearsed yet): stop the `kanidm` container, restore a file from
  `store/authentication` (or from restic) and run
  `kanidmd database restore -c /data/server.toml <file>` inside the image, then start
  it. People keep their passkeys. After a restore from an old backup, secrets of clients
  created since are gone: re-run `scripts/kanidm-oauth2-secret.sh` for them.
  Rehearse this once on router-test's Kanidm (VM 230, `id-test.vanwaaij.com`).

## Proxmox

Realm `kanidm` (OpenID) on pve, in `/etc/pve/domains.cfg`. It was added with
`pveum realm add`, the secret read from 1Password `kanidm-oauth2-proxmox` and piped over
SSH stdin, never in argv. Scopes `email profile` (Proxmox adds `openid`),
username claim `preferred_username`, `autocreate 0`. `thijs@kanidm` was created by
hand with the Administrator role on `/`.

## Known limits

- **Names on the LAN**: UniFi has a local DNS record `*.vanwaaij.com` to `10.0.10.110`
  (the router), so LAN devices (and pve) reach every site without hairpin NAT. Before
  2026-10-20 UniFi answered with the WAN address and LAN devices without Tailscale could
  not reach any of them. On the tailnet the router's CoreDNS does the same job.
- **Nextcloud** runs with `allow_local_remote_servers` on (needed to reach Kanidm through
  the tailnet), which turns off Nextcloud's SSRF guard instance-wide. A follow-up could
  add an egress filter. Also: the username groups survive removing a member, and a
  member whose name equals a local account (such as `admin`) would link to it; do not
  name a person like a local account. The same goes for Jellyfin users (finding 54).
- **Public wifi**: `id` and `auth` were reported unreachable from public wifi (public DNS
  answers with the WAN IP and both answer from outside). Cause unknown, waiting for
  details (device, Tailscale state, error).
- Open findings with numbers 35 to 50 and later in `docs/homelab.md`.
