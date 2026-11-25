# Design: voice/text task routing to named Discord channels, with instant acks

Builds on the merged livetalk step 1 (`docs/agent.md` "Fast voice model" /
"Bilingual STT", `modules/server/agent/hermes.nix`). This is step 2: routing
a request made in a generic channel or voice channel into a named project
channel's own session, with an instant ack first.

## Goal (owner's words, paraphrased)

- In a generic voice/text channel (`#general`) he says "this should be part
  of the Orakel theatre chat, continue there": the bot creates the task in
  the named channel and the work and updates continue there, with that
  channel's own session/model/project context, like he messaged it directly.
- An agent works in the background; the bot relays short status updates.
- Instant ack: anything slow (terminal commands, delegation) gets an almost
  immediate reply from the fast voice model (Haiku, `auxiliary.voice_chat`)
  before the real work finishes, in voice and text.
- Channel lookup by name via the bot's own Discord API, no fixed list, any
  channel the bot can see. A custom plugin may be needed.
- Lodestar review gate stays: investigate freely, never push/deploy without
  the owner's go-ahead.

## Current state, with evidence

**Livetalk step 1 (merged, `unstable`).** `settings.auxiliary.voice_chat`
routes any `MessageType.VOICE` turn to Haiku (`agent/voice_turn_route.py:135
-171` `begin_voice_turn_route`) — a whole-turn model swap, including tool
calls (`:153-166`), falling back to the main model only when the
conversation outgrows the voice model's context (`:64-71,158-161`). No
fast-ack/slow-continue split exists in it (docstring, `:1-14`). TTS is now
Kokoro; live voice-channel playback has an open, unrelated bug (diagnostics
only, `docs/agent.md`). `delegation.model` stays unset so delegated work
keeps the channel's main model.

**`delegate_task`: background + re-entry.** Returns a dispatch handle
immediately (`tools/delegate_tool_dispatch.py:387-391`); its schema tells
the model to end the turn and never poll (`tools/delegate_tool.py:710-718`).
On completion, `tools/async_delegation.py:1112` queues the result;
`gateway/run_notifications.py:931-1018` `_inject_watch_notification` builds
a synthetic `MessageEvent(message_type=TEXT, internal=True)` and admits it
via `gateway/wake.py:97` `admit_internal_event`, which calls
`adapter.handle_message(event)`. Because it's `TEXT` not `VOICE`,
`gateway/run_voice.py:371-399` only speaks it back in `voice_mode == "all"`.

**`deliver_wake`: the generic "start a turn in chat X" primitive.**
`gateway/wake.py:67` `deliver_wake(adapter, *, text, source=None, ...)`
builds the same kind of synthetic event from a `SessionSource` and admits
it the same way. Kanban's own wake already uses this for an **arbitrary**
chat, not just one with a pending completion:
`gateway/kanban_watchers_notifier.py:646-672` builds `SessionSource(
platform=self.plat, chat_id=sub["chat_id"], chat_type=..., user_id=...)`
straight from a notify-sub row and calls `deliver_wake(...)`. Addressing is
purely by `chat_id` — the target need not be "active".
`gateway/platforms/base.py:3915-3918` `handle_message`: "returns quickly by
spawning a background task" — so `deliver_wake` returns fast; the real work
runs as a background task in the target channel's own session.
`gateway/session.py:69-97` `SessionSource` has every field a Discord route
needs (`platform`, `chat_id`, `chat_type`, `user_id`, `scope_id`/`guild_id`).

**Per-channel model/prompt/project context is "for free".**
`platforms.discord.channel_overrides[channel_id]` is a typed
`ChannelOverride(model, provider, system_prompt, ...)`
(`gateway/config.py:380-393`); `channel_prompts` is free-text-only
(`gateway/platforms/base.py:1747-1757`). Both are resolved fresh **every
turn** by `chat_id` (`gateway/run_config_loaders.py:154-186`, docstring
"resolved from the CURRENT profile's config on every call"), never cached.
There is no config-level channel-to-project binding — that's the
`channel-project-context` skill (infers a repo from the channel name at
prompt time). So a turn started in channel X by any means already gets
channel X's own model/prompt/project behaviour.

**Plugin system can reach the Discord client.** Manifest:
`hermes_cli/plugins_manifest.py:33-40` (`provides_tools`, `provides_hooks`,
`requires_hermes`); local example `modules/server/agent/plugins
/local-stt-vocab/plugin.yaml` + `__init__.py:77-79`. A plugin gets a live
handle on the real `discord.py` `commands.Bot` via
`hermes_cli/plugins_context.py:637-652` `register_platform_handler(platform,
factory)` (`factory(native, adapter)` at `connect()`), and registers a
model-callable tool via `plugins_context.py:270-300` `register_tool(...)`.
`plugins/platforms/discord/adapter.py:2538-2563` already enumerates
`guild.text_channels` internally, just not exposed to plugins.
`tools/send_message_tool.py:28-30` is deliberately **not** model-callable
("the agent must not fire cross-platform messages on its own") — a
precedent to respect, not reuse directly: routing needs its own gated tool.

## Options considered

**Kanban as task backbone.** `Task` (`hermes_cli/kanban_db.py:595-640`) has
`assignee` (a profile), `status`, `project_id` — no channel field. The
dispatcher polls every ~60s (`gateway/kanban_watchers_dispatcher.py:120
-217`) and runs tasks in a **new, isolated** session
(`gateway/session_kanban.py:61-152`), not the target channel's own session;
channel targeting only exists for relaying status back to the *creator*
chat (`tools/kanban_tools.py:1183-1257`). Rejected: async/polled, no channel
field, relay only goes back to the creator.

**Custom plugin — chosen.** A plugin tool resolves the channel name against
the live guild list and starts a real turn there with `deliver_wake`, the
same primitive kanban's own wake already uses for arbitrary chats. No new
gateway code or storage.

## Chosen design

`#general` turn: owner asks for routing. The fast model emits a one-sentence
ack plus a `route_task(channel, task)` call, in the same response, then ends
the turn. `route_task` resolves the channel, builds a `SessionSource`, and
calls `deliver_wake`, which returns as soon as `handle_message` **admits**
the event — not when the target turn finishes. The real work then runs as
its own background turn in `#orakel-theater`, using that channel's own
model/prompt, posting its own replies there.

### Plugin: `discord-channel-router`

Directory plugin, shaped like `local-stt-vocab`
(`modules/server/agent/plugins/discord-channel-router/`), no
`requires_hermes` (avoids the known `0.0.0` install-stamp gate bug already
patched for other plugins in `hermes.nix`).

```yaml
name: discord-channel-router
provides_tools: [list_channels, route_task]
```

`register(ctx)` calls `ctx.register_platform_handler("discord",
_capture_discord_client)` to stash the live `commands.Bot`/`DiscordAdapter`,
then `ctx.register_tool("list_channels", ...)` and
`ctx.register_tool("route_task", ...)`.

- `list_channels(query)`: walks `bot.guilds` -> `guild.text_channels`
  (mirrors `adapter.py:2538-2563`), fuzzy-matches `query`
  (`tools/fuzzy_match.py`), returns `[{id, name, guild_id}]` live every call
  — no fixed list.
- `route_task(channel, task)`: resolves `channel` the same way (on more than
  one match, asks for clarification instead of guessing); builds
  `SessionSource(platform=Platform.DISCORD, chat_id=resolved_id,
  chat_type="channel", scope_id=guild_id, user_id=<owner's Discord ID from
  DISCORD_ALLOWED_USERS>)`; calls `await deliver_wake(discord_adapter,
  text=task, source=source, notification_category="result")`; returns a
  short confirmation ("Routed to #orakel-theater.") to the calling turn.

### Ack behaviour

Two parts — nothing built-in does both:

1. **Fast model for the generic channel's text turns**, matching the voice
   path: add `platforms.discord.channel_overrides.<generalChannelId>.model
   = "claude-haiku-5-5"` (the same id as `auxiliary.voice_chat`).
2. **Prompting for "ack first".** Neither `display.*`
   (`gateway/session_config.py:91-106`) nor `channel_prompts` has a
   structural ack field. Add one instruction to the generic channel's
   `channel_prompts` (and the voice prompt): answer in one short sentence
   first, call `route_task`/`delegate_task` in the same turn, then end the
   turn — never make the owner wait for real work before hearing anything.
   This works because `route_task` and `delegate_task` both return almost
   instantly, so the ack sentence goes out before the routed work finishes.

### Update relay

No new relay code: the turn `deliver_wake` starts in `#orakel-theater` runs
with that channel's own `channel_overrides`/`channel_prompts` (confirmed
above) and posts its own replies there through the normal adapter path,
exactly like a message typed there directly. If the owner wants terser
updates for routed tasks specifically, that's a line in that channel's own
`channel_prompts`, not new code. The result is **not** relayed back to
`#general` or the voice channel — "continues there" is a one-way handoff,
per the owner's own wording.

## Config changes (`modules/server/agent/hermes.nix`)

```nix
extraPlugins = [
  # ... existing gemini-stt, local-stt-vocab ...
  (pkgs.runCommandLocal "discord-channel-router" { } ''
    cp -r ${./plugins/discord-channel-router} $out
  '')
];
settings.plugins.enabled = [ "gemini-stt" "local-stt-vocab" "discord-channel-router" ];
settings.platforms.discord.channel_overrides.${generalChannelId}.model = "claude-haiku-5-5";
settings.platforms.discord.extra.channel_prompts.${generalChannelId} =
  "<ack-then-route instruction, see Ack behaviour>";
```

`generalChannelId` is a new `let` binding next to `DISCORD_HOME_CHANNEL`, a
literal snowflake in the same style.

## Security

- **Who may trigger it:** the bot only admits messages from
  `DISCORD_ALLOWED_USERS`; a turn that calls `route_task`/`delegate_task`
  exists only because that gate already passed. No new entry point.
- **No identity bypass:** the allow-user/role check is in the adapter's
  inbound path (`plugins/platforms/discord/adapter_slash_auth.py:83`),
  ahead of `handle_message`. `route_task` sets the synthetic event's
  `user_id` to the owner's own ID, so the injected turn is attributed to
  him, not to an unauthenticated actor.
- **Channel allow = any visible channel**, per the owner's ask. Mitigated
  by refusing to guess on an ambiguous name match, and by always naming the
  resolved channel back in the confirmation.
- **No secrets in logs:** only channel IDs/names and task text are logged;
  `DISCORD_BOT_TOKEN` stays opnix-sourced, untouched.
- **Review gate unchanged:** this plan only adds a plugin directory and
  three `hermes.nix` keys; nothing here authorizes push, merge, promote, or
  deploy without the owner's go-ahead.

## Tests (`tests/agent.nix`)

Owner rule: real invariants, never a literal-config echo.

- Plugin is in `extraPlugins` **and** `settings.plugins.enabled` (declared
  but not enabled is a silent no-op — assert both).
- `channel_overrides.<generalChannelId>.model` equals
  `auxiliary.voice_chat.model` (the two fast-model settings can't drift
  apart) **and** differs from `settings.model.default` (same shape as the
  existing "stays a different, Haiku-family model" assertion).
- `channel_prompts.<generalChannelId>` is set and non-empty.
- `generalChannelId` differs from `DISCORD_HOME_CHANNEL` (catches a
  copy-pasted id).

Behavioural proof (by hand once implemented, not during this read-only
phase, not in `tests/agent.nix`): call the plugin's `route_task` handler
against a fake adapter whose `handle_message` has an artificial delay;
assert the call returns before that delay completes, and that the
`SessionSource` it built carries the resolved `chat_id` and the owner's
`user_id`.

## Rollout

1. Build the plugin and config changes on a branch, same shape as
   `local-stt-vocab`; no behaviour change until `plugins.enabled` lists it.
2. Dry-run `list_channels` alone against iris's real guild, by hand, before
   wiring the ack-then-route prompt.
3. Add `route_task` and the ack instruction together; test from `#general`
   against a throwaway channel before a real project one.
4. Promote through Lodestar only after the owner reviews the PR.
5. Independent of the live VC TTS playback bug: text/voice-note routing
   work without it; only "spoken result inside a live VC" needs that fixed.

## Open questions for the owner

1. Which channel is "the generic channel" for `channel_overrides`/
   `channel_prompts` — `DISCORD_HOME_CHANNEL`, or a new `generalChannelId`
   (assumed here)?
2. Ambiguous channel-name match: always ask (assumed here), or pick the
   closest match silently?
3. Should `route_task` post a visible "received from #general" note in the
   target channel, or just let the agent's reply be the first thing there
   (assumed here)?
4. Should a result ever route back to the originating voice channel, or is
   "continues there" always final (assumed here; revisit once the VC
   speak-back bug is fixed, if still wanted)?
5. Haiku override scope: one named general channel only (assumed here), or
   every channel with no explicit `channel_overrides`?
