# iris: a VM for Hermes Agent

Status: agreed in conversation 2026-11-09 up to section 1 (VM and host); sections 2–6
written for review. Implementation plan follows once this is approved.

## Why

Thijs wants a personal AI agent, [Hermes Agent](https://github.com/NousResearch/hermes-agent)
(Nous Research), always on, reachable from Discord, that can look at the homelab and do
work for him, without paying per token.

## Goal

- A NixOS VM **iris** (VM 101) runs Hermes as a service, managed like every other server
  (thin host file, one module, Lodestar applies it).
- Thijs talks to it through a **Discord bot** (his own); only his Discord user answers.
- Models are paid by **plans, not tokens**: ChatGPT plan (Codex OAuth) as the main model,
  free OpenRouter models as fallback and for side tasks, coding delegated to **Claude
  Code** on his Claude plan.
- It can **read** the homelab (metrics, logs, alerts) and change nothing outside iris.
- Its web dashboard is reachable **on the tailnet only**.
- Success: a DM to the bot gets an answer from the ChatGPT model; "is prod healthy?"
  is answered from Grafana; "write me a script for X" runs Claude Code on iris; the
  dashboard opens at `https://agent.vanwaaij.com` from a tailnet device and not from the
  internet.

Out of scope (later, separate design): write access to the homelab (applying changes,
SSH to other hosts, Lodestar actions); Anthropic or OpenAI API keys; a Lodestar read API
token (Lodestar has none today).

Name: the host is `iris` (messenger of the gods, like Hermes) because `hermes` is the
Framework laptop. The dashboard is not `hermes.vanwaaij.com` either: a Tailscale Service
named like a device loses its MagicDNS name to the device (`docs/lodestar.md`, the
`svc:cache` note), and the laptop is the device `hermes`.

## Decisions

| Question | Choice | Why |
|---|---|---|
| How Hermes runs | Upstream NixOS module, **native** systemd (not its OCI container mode, not docker-compose) | Same shape as every other server; the VM is the sandbox; updates through the flake |
| Chat interface | Discord gateway, `DISCORD_ALLOWED_USERS` = Thijs only | Bot made by Thijs |
| Main model | OpenAI Codex provider, ChatGPT plan, device-code OAuth | Plan usage, not tokens |
| Fallback / side tasks | OpenRouter `:free` models, API key | Free; Thijs picks other models at runtime |
| Anthropic | Not a Hermes provider. Claude Code CLI via Hermes's bundled `claude-code` skill, logged in with Thijs's Claude plan | Hermes's Anthropic OAuth only bills Max "extra usage" credits, never the plan allowance |
| Homelab access | Read-only: Grafana Viewer service account through `mcp-grafana` | Covers Prometheus, Loki, alerts with one token |
| Dashboard | `agent.vanwaaij.com`, `public = false`, Kanidm gate, plus Hermes's own password | Tailnet only, same pattern as Grafana |

## 1. VM and host (agreed)

- `hosts/servers/iris.nix`: `type = "server"`, `useDefaultHardware = true`,
  `isHomeServer = true`, `netInterface = { ip = "10.0.10.101"; prefixLength = 24; }`,
  `tags = [ "tag:iris" ]`, `fleet = true`, `options.homelab.agent.enable = true`.
- VM 101 on `pve`, cloned from `nixos-26.05-template` (9000): 4 vCPU, 6 GB RAM, 40 GB
  on local-lvm, `cpu: host` (opnix), `onboot: 1`. 101 is in the 100–109 core & personal compute band
  (`docs/vmids.md`). `pve` had about 15 GB RAM available on 2026-11-09.
- Tailscale policy: `tag:iris` in `tagOwners`, owner `tag:nixos`. `tag:nixos` already
  reaches `svc:nix-cache`, so iris substitutes from the fleet cache.
- Bootstrap once: `sudo opnix token set`, enrol in Lodestar (`docs/lodestar.md`).
- Inventory: add iris to `docs/homelab.md` and the machine table in `AGENTS.md`.

## 2. The Hermes module

New input `hermes-agent = { url = "github:NousResearch/hermes-agent"; inputs.nixpkgs.follows = "nixpkgs"; }`
(check that it builds against our nixpkgs; if not, let it keep its own). Its NixOS
module is imported for every host (the module is inert unless enabled, so the
"every module is always imported" rule holds); Linux-only, so the import sits behind
`hostPlatform.isLinux` like other Linux-only inputs.

`modules/server/agent/hermes.nix`, gated on `options.homelab.agent.enable`:

- `services.hermes-agent.enable = true`, native mode (`container.enable = false`),
  user/group `hermes`, `stateDir = "/var/lib/hermes"` (holds `.hermes/` =
  `HERMES_HOME`: config, memory, skills, sessions, `auth.json`).
- `settings` (rendered to `config.yaml`):
  - main model: provider `openai-codex`, a Codex model as default.
  - `fallback_providers`: OpenRouter with a `:free` model. Thijs switches models at
    runtime (`/model`); the repo only sets defaults.
  - auxiliary tasks (compression, vision): OpenRouter free model, so side work doesn't
    eat the ChatGPT plan.
  - Discord: allowed users = Thijs's user ID (a plain value in the module, not a
    secret), `require_mention` in server channels, DMs allowed.
- `environmentFiles`: one file that opnix renders with `DISCORD_BOT_TOKEN`,
  `OPENROUTER_API_KEY` and the Grafana token (section 3).
- `extraPackages`: `claude-code`, `codex`, `git`, `gh`, `jq`, `ripgrep`, `nix` on the
  agent's PATH. Claude Code's auto-updater is off (`DISABLE_AUTOUPDATER=1`); updates
  come with `nix flake update`.
- `mcpServers.grafana`: `mcp-grafana` from nixpkgs, `GRAFANA_URL =
  https://grafana.vanwaaij.com`, token from the environment file.
- Backend (dashboard): `backend.mode = "dashboard"`, bound to `10.0.10.101:9119`,
  password auth (password from opnix). Firewall: 9119 open to the router
  (`10.0.10.110`) only.
- Hardening: `hermes` has no sudo, no SSH keys, isn't in `wheel`; the upstream unit's
  systemd hardening stays on. The agent writes only under `/var/lib/hermes` and `/tmp`.

Interactive logins, once, after the first switch (documented in `docs/agent.md`):

```sh
ssh iris
sudo -u hermes -i hermes auth add openai-codex     # device code: open URL, enter code
sudo -u hermes -i claude                           # Claude plan login (browser URL)
```

Tokens land in `/var/lib/hermes` (`.hermes/auth.json`, `~/.claude/`); Hermes and Claude
Code refresh them. A dead refresh token shows up as a re-auth message in Discord.

## 3. Secrets

1Password vault **Homelab**, read by opnix (`modules/server/secrets/opnix.nix`):

| Item | Field | Use |
|---|---|---|
| `iris-discord` | `token` | `DISCORD_BOT_TOKEN` |
| `iris-openrouter` | `credential` | `OPENROUTER_API_KEY` |
| `iris-grafana` | `token` | Grafana Viewer service account token for `mcp-grafana` |
| `iris-dashboard` | `password` | Hermes dashboard password |

Thijs creates the Discord bot and the OpenRouter key; the Grafana service account is
created in Grafana (Viewer role) and its token stored by hand once (Grafana's
provisioning can't mint tokens). The ChatGPT and Claude logins are **not** in 1Password:
they are OAuth tokens that rotate, owned by Hermes/Claude Code on iris (section 2).

## 4. Network and dashboard

- Route `homelab.routes.agent` (in the agent module, the way services declare their
  routes): `host = "agent.vanwaaij.com"`, `backend = "http://10.0.10.101:9119"`,
  `public = false`, `tailnet.enable = true`, `auth.gate = true`.
- Kanidm: app `agent` in `homelab.identity.access` with `gate = true`, members
  `[ "thijs" ]`.
- Tailscale policy: Service `agent` auto-approved for the router; grant
  `tag:iris → svc:grafana` tcp:443 (for `mcp-grafana`). After creating the Service:
  `tailscale serve drain svc:agent` + `advertise svc:agent` on the router.
- The router already reaches the LAN, so no grant is needed for router → iris:9119.
- Discord, ChatGPT, OpenRouter and Anthropic are outbound HTTPS only; nothing on iris is
  exposed to the internet.

## 5. Backups and monitoring

- Backups: `/var/lib/hermes` is the only state worth keeping (memory, skills,
  sessions, OAuth tokens). It goes into the restic `store` repo
  (`modules/server/backup/homelab.nix`). The Hermes state is local to iris, not on
  TrueNAS, so either (a) a nightly `hermes backup` / tarball to an NFS share on TrueNAS
  `store/internal/iris` that the existing ZFS snapshot + restic run picks up, or (b) a
  restic job on iris itself. Choose (a): one restic setup, same as Kanidm's backups.
- Monitoring: `fleet = true` and the monitoring agent give node metrics and logs like
  every server. Add a systemd-unit-failed alert for `hermes-agent.service` if the
  generic unit alert doesn't already cover it. Log budget: default 200 MB/day; raise
  it if the gateway is chatty.

## 6. Failure and safety

- **Prompt injection through Discord or fetched pages**: the bot answers only Thijs's
  user ID; the agent can't reach other hosts except Grafana read-only and the fleet
  cache; it holds no credentials that write anywhere except its Discord bot.
- **OAuth expiry**: Hermes reports a typed re-auth message; fix is the login commands in
  section 2. Claude Code likewise.
- **ChatGPT plan limits hit**: Hermes falls through to `fallback_providers`
  (OpenRouter free).
- **Bad upstream release**: Hermes is a pinned flake input; the build gate catches
  build failures; roll back with the previous generation in GRUB.
- **Disk fills** (sessions, Claude Code caches): 40 GB disk; the disk-space module
  collects Nix garbage under 1 GiB free; Hermes's own disk banner warns.

## Testing

- `nix eval` of iris and the five usual hosts; `nix flake check --no-build`.
- Build iris on nixos-manager (bundle flow in `AGENTS.md`); the cache then has it.
- After rollout: the success checks in **Goal**, plus `curl https://agent.vanwaaij.com`
  from outside the tailnet fails, and the bot ignores a DM from another Discord account.

## Open items for Thijs

- Discord user ID (for the allowlist) and the bot (token into `iris-discord`; Message
  Content and Server Members intents on; private bot invited with the manual URL,
  permissions `309237763136`).
- OpenRouter key into `iris-openrouter`.
- Which ChatGPT plan (Plus/Pro); Hermes doesn't document how Codex limits count.
