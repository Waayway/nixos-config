# Orakel Theater on hestia

How `hetorakeltheater.nl` (production) and `staging.hetorakeltheater.nl` (staging) run on
hestia, the Hetzner hosting node. The cut-over from the legacy `primary-server` follows the
runbook in the orakel repository (`docs/plans/cutover-runbook.md`); this page is the
nixos-config side. Design: `docs/plans/2026-11-10-lodestar-hosting-platform-design.md`.

## What runs where

All on hestia (`hosts/servers/hestia.nix`: `hosting.traefik.public.enable`,
`hosting.orakel.enable`), configured in `modules/server/hosting/orakel.nix`:

| | production | staging |
|---|---|---|
| orakel instance | the module's default instance (`services.orakel`) | `services.orakel.instances.staging` |
| units | `orakel-backend`, `orakel-frontend` | `orakel-staging-backend`, `orakel-staging-frontend` |
| user, data | `orakel`, `/var/lib/orakel` (`orakel.db`, `uploads/`) | `orakel-staging`, `/var/lib/orakel-staging` |
| ports (loopback) | backend 8080, frontend 3000 | backend 8081, frontend 3001 |
| commands as the unit | `sudo orakel-ctl <command>` | `sudo orakel-ctl-staging <command>` |
| `APP_ENV` | `production` | `production` (runbook F9), Mollie **test** key |
| scheduler | off (on after the cut-over boot, runbook §5.3) | off |
| Traefik site | `orakel`: `/api` → backend, rest → frontend | `orakel-staging`: same, behind basic auth except `/api/health` and `/api/tickets/webhook` |

Traefik (`modules/server/hosting/traefik.nix`, `hosting.traefik.public`) answers on 80
(redirect to https) and 443 with Let's Encrypt certificates (HTTP-01, design D7; account and
certificates in `/var/lib/traefik/acme.json`). A certificate can only be issued once the
name's DNS points at hestia: before that, test with
`curl --resolve hetorakeltheater.nl:443:<hestia IP> -k …` (runbook F11/Q7). `/api` goes
straight to the backend, not through Next (runbook F13). Traefik does not trust
`X-Forwarded-*` from the internet, so the backend's rate limiters see the real client
address. The tailnet side (`hestia-whoami`) is unchanged.

`TZ`/`TIMEZONE` (`Europe/Amsterdam`) and `DB_PATH` come from orakel's module; the non-secret
SMTP values are the legacy ones. `sqlite3` is on the system path for the runbook's
`.backup`, integrity checks and id offset.

## Secrets: 1Password items (vault Homelab)

The item and field names are the contract between this repo and the vault: create them
before the first deploy (`op --account … item create --vault Homelab …`, AGENTS.md). opnix
writes them root-only (`0400`) to `/var/lib/opnix/secrets/<name>`; nothing is in the store.

| Item | Field | opnix name | Content | Read by |
|---|---|---|---|---|
| `orakel-production` | `env` | `orakelProductionEnv` | env file: `SECRET_KEY` copied **verbatim** from the old server (runbook F4), `SMTP_PASSWORD`, `TURNSTILE_SECRET`, `TURNSTILE_SITE_KEY`; `QR_SECRET` **only** if the old server sets one | `orakel-backend` (EnvironmentFile), `orakel-ctl` |
| `orakel-production` | `mollie-api-key` | `orakelProductionMollie` | the live Mollie key, nothing else | `orakel-backend` (LoadCredential) |
| `orakel-staging` | `env` | `orakelStagingEnv` | env file: a **new** random `SECRET_KEY`, `SMTP_PASSWORD`, Turnstile keys for the staging host | `orakel-staging-backend`, `orakel-ctl-staging` |
| `orakel-staging` | `mollie-api-key` | `orakelStagingMollie` | a Mollie **test** key (`test_…`) | `orakel-staging-backend` |
| `orakel-staging` | `htpasswd` | `hostingTraefikAuthOrakelStaging` | htpasswd lines for staging's basic auth (`htpasswd -nB <user>`) | Traefik (owner `traefik`) |

A changed value restarts the unit that reads it (opnix change detection, polled every 6 h or
on a switch).

## Before the first real deploy

1. **The orakel input.** `flake.nix` points `inputs.orakel` at the private GitHub repository
   on a branch that is not pushed yet. Push it, set `ref` to the branch that is merged, run
   `nix flake lock --update-input orakel` and commit the lock. Until then everything is
   evaluated with
   `--override-input orakel "git+file:///var/lib/hermes/workspace/repos/orakel-nix2?submodules=1"`.
2. **Who has to fetch it.** Every host whose evaluation reads hestia's configuration needs
   the orakel source: hestia itself, and router, router-test, identity and monitor (they
   collect routes, access and monitoring targets from every configuration), plus the cache
   VM when it builds them, and `nix flake check` anywhere. Either read access to the
   repository for those hosts (runbook BUILD-10: deploy key on the build gate) or the
   locked source substitutable from `cache.vanwaaij.com`. Decide this before merging, or
   those hosts' Lodestar applies fail at evaluation.
3. **The 1Password items** of the table above.
4. **DNS** for `staging.hetorakeltheater.nl` (runbook F1/G11) and, at the window, for
   `hetorakeltheater.nl` (owner).
5. **`tag:hestia`** in the Tailscale policy (hosts/servers/hestia.nix).
