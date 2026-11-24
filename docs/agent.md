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

- Main: Thijs's Claude plan through Anthropic OAuth (`anthropic`, default
  `claude-sonnet-5-5`).
- Fallback: the ChatGPT plan through Codex OAuth (`openai-codex`, `gpt-6-sol`), used if
  Anthropic is unavailable. Side tasks (summaries, image reading) run on the main model
  too. Free OpenRouter as a second fallback was designed and skipped for now
  (2026-11-09); to add it, put the key in 1Password `iris-openrouter`/`credential`, add
  it to `secrets.nix` (`need OPENROUTER_API_KEY …`) and extend `fallback_providers` in
  `hermes.nix`.
- Coding: Hermes's bundled `claude-code` skill runs Claude Code on iris, on Thijs's
  Claude plan. The `codex` CLI is there too.

Switch models at runtime with `/model` in Discord or `hermes model` on iris. To change
the defaults, edit `settings.model` / `fallback_providers` in `hermes.nix`.

There is no Anthropic or OpenAI API key on purpose: both providers above are OAuth
logins against a plan allowance (Claude Max "extra usage" credits for Anthropic, the
ChatGPT plan for Codex), never a pay-per-token key.

## Voice

Spoken replies in Discord (not a live voice-channel bot, just TTS on normal text
messages): `settings.tts` picks free Edge TTS (`tts.provider = "edge"`, ships in the
default package, no extra dependency group needed).

STT (transcribing voice messages) is the community `ajk0x00/hermes-gemini-stt` plugin
(`settings.stt.provider = "gemini"`, model `gemini-3.8-flash`), installed declaratively
via `services.hermes-agent.extraPlugins` (pinned to a reviewed commit, no
`extraPythonPackages` needed — its only dependency, `httpx`, already ships with
Hermes) and turned on via `settings.plugins.enabled`. This is the
one pay-per-use key on iris on purpose: free local Whisper was tried first
(`stt.provider = "local"`) but the quality at the free tiers (`base`, even `large-v3`)
wasn't good enough; Gemini Flash's cost at Thijs's usage (~EUR2/month) was accepted
instead. `GEMINI_API_KEY` comes from opnix (`secrets.nix`, 1Password item
`iris-gemini`), never a plaintext value in `hermes.nix`.

Transcription quality for project-specific names/terms (e.g. "Orakel" was heard as
"Oracle") is improved with a vocabulary/context hint forwarded to every voice
message. Hermes has a core, *static* `settings.stt.prompt` config key for this, but
a plain config value means every edit needs a Nix change and a redeploy — so instead
this uses our own `local-stt-vocab` plugin
(`modules/server/agent/plugins/local-stt-vocab`), via Hermes's `pre_transcription`
hook:
- Its bundled `default-vocabulary.md` is the Nix-committed **starting default** only.
- On first use it copies that into a **local, writable file outside the Nix store**
  (`plugin_data_dir("local-stt-vocab")/voice-vocabulary.md` — i.e.
  `$HERMES_HOME/plugin-data/local-stt-vocab/voice-vocabulary.md`) and never touches
  that copy again, so edits survive every future rebuild.
- Any agent session on iris edits that live file directly (`write_file`/`patch`, no
  PR, no rebuild) to add or remove a term; it takes effect on the very next
  transcription. Both files share the same format: the last non-blank line is read
  verbatim as the prompt.

Turn spoken replies on per conversation from Discord itself (not a `hermes.nix`
setting):
- `/voice on` — speak only when you replied with a voice message
- `/voice tts` — speak every reply
- `/voice off` — text only (default)

Send a voice message in Discord (DM or the home channel, since
`DISCORD_REQUIRE_MENTION=false`) to talk to iris by voice from a phone — no separate
app needed, Discord already has push notifications and voice messages. A live
Discord voice-channel bot (`/voice join`) is a separate, heavier mode (needs
`Connect`/`Speak` permissions and privileged intents); Thijs has used it, but see the
known bug below — spoken replies currently never play back in the voice channel.

### Fast voice model

Any turn tagged `MessageType.VOICE` (a Discord voice-note reply or a live voice-channel
turn) runs on `auxiliary.voice_chat` instead of the main Sonnet/Opus model — a
livetalk-style voice session wants an instant small-talk reply, not full-model latency.
Set in `hermes.nix`:
```nix
auxiliary.voice_chat = {
  provider = "anthropic";
  model = "claude-haiku-5-5";
};
```
`claude-haiku-5-5` is the newest Haiku id this Hermes install's live model catalog
knows for the `anthropic` provider (`~/.hermes/models_dev_cache.json`; the package's
own bundled fallback catalog, `hermes_cli/models_catalog_static.py`, only has the
older `claude-haiku-4-5-20251001` and is a disk-cache-unavailable fallback, not the
account's real catalog). Hermes falls back to the main model by itself once a
conversation's history no longer fits the cheaper model's context window
(`agent/voice_turn_route.py`). `delegation.model`/`delegation.provider` are
deliberately left unset: when the voice turn hands real work off with
`delegate_task`, the delegated work keeps running on whichever model its own
channel/session already uses, instead of being forced onto Haiku.

### Bilingual STT

Thijs speaks both Dutch and English, often in the same conversation. The gemini-stt
plugin's `language_mode` setting (`plugins.entries.gemini-stt.settings.language_mode`,
read via its own `ctx.get_config`, **not** `stt.gemini.*`, which is Hermes's own
tree) defaults to `"hint"`: it forces every utterance to be transcribed as
`stt.gemini.language` (`"en"`). Set to `"auto"` in `hermes.nix` so Gemini detects the
spoken language per utterance instead — true per-utterance code-switching, one
Gemini call, no second STT pass. `stt.gemini.language` stays set but is now inert
(kept as the default if `language_mode` is ever switched back to `"hint"`).

### Diagnostic logging (temporary)

`sitecustomize.py` (same file as the opus/plugin-gate fixes above) also wraps 8
functions in the voice-reply pipeline (`BasePlatformAdapter._wants_auto_tts`,
`_synthesize_auto_tts`, `_play_tts_file`; the Discord adapter's `play_tts` and
`play_in_voice_channel`; `GatewayVoiceMixin._should_send_voice_reply`,
`_toggle_adapter_auto_tts_set`, `_sync_voice_mode_state_to_adapter`) to log one
`logger.warning` line per call, prefix `voice-diag:` (visible in both `gateway.log`
and `errors.log`, since `logger.warning` clears `errors.log`'s WARNING+ threshold),
with the real inputs, adapter identity (`id(...)`), and the real decision — then
return/raise exactly what the original did (proven behavior-preserving against the
live pinned interpreter in `.../cache/scratch/voice-b1/harness.py`). It exists to
pin down the open bug above: `/voice join` + `/voice on` leave the bot joined and
listening, but no spoken reply is ever played back, and neither TTS gate logs so
much as a warning on the failing path — something only a live trace of these 8
calls' actual inputs (in particular `id(adapter)`, to catch an adapter replaced by
a reconnect after `/voice on` populated a different instance's enabled-chats set)
can pin down. **Remove this whole block once that live trace identifies the real
cause and a real fix lands** — it is diagnostics only, not a fix.

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

## Per-project packages (direnv)

Toolchains are not installed on iris. Each project in
`/var/lib/hermes/workspace/repos/<project>` declares what it needs in its own
`flake.nix` (a `devShell`) and an `.envrc` containing `use flake`.
`modules/server/agent/direnv.nix` enables direnv with nix-direnv (cached shells that
survive garbage collection).

```sh
cd /var/lib/hermes/workspace/repos/<project>
echo 'use flake' > .envrc
direnv allow                      # an .envrc does nothing until allowed (nothing is trusted in advance)
direnv exec . cargo build         # non-interactive shells (the agent's tools): run a command inside
```

Interactive shells load the environment on `cd` through the shell hook. A change to
`flake.nix` or `.envrc` needs `direnv allow` again.

## Logins (by hand, once)

After the first start, and again whenever the bot says a login expired:

```sh
ssh iris
sudo -u hermes -i hermes auth add anthropic      # device code / OAuth URL for the Claude plan
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
Grafana service account `iris` with role Viewer.

Read-only SSH (2026-11-11): every NixOS server has a user `iris`
(`modules/server/users/iris.nix`) outside `wheel` and in `systemd-journal`: it can read
logs, unit status, `/etc` and the Nix store, not secrets or service state, and has no
sudo. iris logs in with Tailscale SSH (`ssh iris@<host>`; no keys) by the policy rule
`tag:iris` → the server tags (`tag:router`, `tag:prod`, `tag:identity`, `tag:monitor`,
`tag:cache`, `tag:manager`, `tag:hestia`) as `iris` only, plus a `tcp:22` grant to the
same tags. Not `tag:nixos`: iris carries it too, and on iris `iris` is the wheel host
user. Laptops and iris itself are not reachable. A new server tag must be added to both
rules. Changes go through this repo, never through this
login. Write access (applying changes, Lodestar actions) is a separate design for later.

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
