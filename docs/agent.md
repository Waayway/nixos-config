# iris: Hermes Agent

iris (Proxmox VM 101, `10.0.10.101`, `tag:iris`) runs
[Hermes Agent](https://github.com/NousResearch/hermes-agent) as Thijs's Discord bot.
Design: `docs/plans/2026-11-09-iris-agent-design.md`. Config:
`modules/server/agent/` (`homelab.agent.enable` in `hosts/servers/iris.nix`).

## What runs

- `hermes-agent.service`: the gateway (Discord bot), user `hermes`, state in
  `/var/lib/hermes` (`.hermes/` is `HERMES_HOME`: `config.yaml`, `.env`, memory,
  skills, sessions, `auth.json`).
- `hermes-backend.service`: the web dashboard on `10.0.10.101:9119`, reachable only from
  the router.
- `hermes-backup.timer`: nightly copy to TrueNAS (below).

Both services are upstream's NixOS module in native mode. `config.yaml` keys set in
Nix win on every activation; anything else you set at runtime (`/model`,
`hermes config set`) stays.

## Who it answers

Only Discord user `137629736993030144` (Thijs), in DMs and in every server channel the
bot can see, without an @mention (`DISCORD_REQUIRE_MENTION=false`,
`DISCORD_IGNORE_NO_MENTION=false`), in the channel itself rather than a thread
(`DISCORD_AUTO_THREAD=false`). Everyone else is ignored. Cron and reminder output
goes to the home channel `1569317421251039294`. To limit it to some channels, set
`DISCORD_ALLOWED_CHANNELS` in `modules/server/agent/hermes.nix`.

## Models

- Main: the ChatGPT plan through Codex OAuth (`openai-codex`, default `gpt-6-sol`).
- No fallback provider yet: summaries and image reading use the main model too. Free
  OpenRouter models as fallback were designed and skipped for now (2026-11-09); to add
  them, put the key in 1Password `iris-openrouter`/`credential`, add it to
  `secrets.nix` (`need OPENROUTER_API_KEY …`) and set `fallback_providers` in
  `hermes.nix`.
- Coding: Hermes's bundled `claude-code` skill runs Claude Code on iris, on Thijs's
  Claude plan. The `codex` CLI is there too.

Switch models at runtime with `/model` in Discord or `hermes model` on iris. To change
the defaults, edit `settings.model` / `fallback_providers` in `hermes.nix`.

There is no Anthropic or OpenAI API key on purpose: Hermes's own Claude login only
bills Max "extra usage" credits, never the plan allowance.

## Claude coding workers (ACP, no tmux)

Iris installs `acpx` 0.22.0 (pinned npm tarball and runtime dependency lock in
`pkgs/acpx/`), nixpkgs' `claude-agent-acp`, and `acpx-claude` in the gateway's
PATH and the system shell PATH. The adapter uses nixpkgs' `claude-code` and its
existing login; this setup does not add an API key or change authentication.
Check `claude auth status --text` for the account actually in use; an ACP success
alone does not prove which billing allowance paid for it.

Use the wrapper, not bare `acpx claude`: it selects the Nix-installed adapter
without runtime `npx` downloads, keeps the adapter command name stable across
package upgrades, and auto-approves ACP tool requests (`--approve-all`), as
explicitly authorized by Thijs. This is not a filesystem sandbox or a global
Claude `bypassPermissions` setting. The worker inherits the Hermes user's access.

```sh
# Run as hermes. Use one named session per task; serialize writers per checkout.
repo=/var/lib/hermes/workspace/repos/lodestar
acpx-claude --cwd "$repo" --format json sessions ensure --name task-123
acpx-claude --cwd "$repo" --format json --timeout 600 prompt -s task-123 \
  'Read AGENTS.md. Implement the requested change and run the tests. Do not push.'
# Follow-up retains the conversation; -s belongs after the prompt subcommand.
acpx-claude --cwd "$repo" --format json prompt -s task-123 'Review your diff.'
acpx-claude --cwd "$repo" status -s task-123
acpx-claude --cwd "$repo" cancel -s task-123
acpx-claude --cwd "$repo" sessions close task-123
```

The wrapper selects its adapter via `--agent`; do not add a positional `claude`
argument. Acpx may label this custom command's agent as `codex` in status text;
the adapter command, not that display label, determines the worker.
Sessions/state live under `~/.acpx/`, separately from Hermes chat history.
This is a CLI integration, not a Hermes worker plugin: Hermes must explicitly
start, inspect, and follow up on tasks. Do not equate process exit with passing
tests; inspect the diff and actual verification output before reporting success.

## Logins (by hand, once)

After the first start, and again whenever the bot says a login expired:

```sh
ssh iris
sudo -u hermes -i hermes auth add openai-codex   # device code: open the URL, enter the code
sudo -u hermes -i claude                          # Claude plan: open the URL, paste the code back
```

The tokens live in `/var/lib/hermes` (`.hermes/auth.json`, `.claude/`), refresh
themselves, and are in the nightly backup. They are not in 1Password.

## Secrets (1Password Homelab, through opnix)

| Item | Field | Use |
|---|---|---|
| `Iris Discord Bot Token` | `credential` | `DISCORD_BOT_TOKEN` |
| `iris-grafana` | `token` | Grafana service account `iris` (Viewer) for `mcp-grafana` |
| `iris-dashboard` | `password`, `secret` | dashboard password (user `thijs`), session key: letters and digits only (the render refuses quotes, backslashes, spaces) |

Upstream copies `environmentFiles` into `.env` at activation, before opnix has
fetched. So the secrets go in another way: a root `ExecStartPre` writes
`/run/hermes-secrets/env` from the opnix files, and both units read it as
`EnvironmentFile` (with `-`: systemd also loads it for that `ExecStartPre`, before it
exists). A missing or empty secret stops the unit with the variable's name in the log.
opnix restarts them when a value changes.

## Dashboard

`https://agent.vanwaaij.com` on the tailnet only (Tailscale Service `agent` on the
router). Kanidm first (group `agent-users`), then Hermes's own login: `thijs` and the
`iris-dashboard` password. Not `hermes.vanwaaij.com`: the laptop is the tailnet device
`hermes`.

## Homelab access

Read-only, through the Grafana MCP server: Prometheus metrics, Loki logs and alerts, as
Grafana service account `iris` with role Viewer. iris holds no SSH keys or write
credentials for other hosts. Write access (applying changes, Lodestar actions) is a
separate design for later.

## Backups and restore

At 01:30 `hermes-backup` writes `hermes-<date>.tar.gz` to
`/var/lib/hermes-backup` (TrueNAS `store/internal/iris`, NFS, iris only; the dataset
is owned by uid 950, `hermes`). It holds SQLite files copied with `.backup` plus a
tar of everything else, and keeps the last 7. The 02:00 snapshot and the restic `store`
repo pick it up.

Restore:

```sh
sudo systemctl stop hermes-agent hermes-backend
cd /tmp && mkdir r && tar -xzf /var/lib/hermes-backup/hermes-<date>.tar.gz -C r
sudo -u hermes tar -xf r/files.tar -C /var/lib/hermes
cd r && find . -name '*.db' -exec sudo -u hermes cp --parents {} /var/lib/hermes/ \;
sudo systemctl start hermes-agent hermes-backend
```

## Troubleshooting

- Bot offline: `journalctl -u hermes-agent`. "privileged Gateway Intents" means
  Message Content or Server Members intent is off in the Developer Portal.
- No token: `sudo ls -l /run/hermes-secrets/env` and `systemctl status opnix-secrets`
  (`sudo opnix token set` if the opnix token is missing).
- Grafana tools fail: check the `iris-grafana` token and the `tag:iris → svc:grafana`
  grant.
