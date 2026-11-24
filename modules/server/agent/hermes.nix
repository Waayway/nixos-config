{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Hermes Agent (github.com/NousResearch/hermes-agent) on iris, from upstream's NixOS
# module in native mode (a systemd service, not its OCI container): a Discord bot for
# Thijs that thinks with his ChatGPT plan and
# hands coding to Claude Code on his Claude plan. Design:
# docs/plans/2026-11-09-iris-agent-design.md; runbook: docs/agent.md.
#
# State in /var/lib/hermes (.hermes/ is HERMES_HOME: config, memory, skills,
# sessions, auth.json). The ChatGPT and Claude logins are made by hand once on iris
# (docs/agent.md) and live there; they are OAuth tokens that rotate, not 1Password
# secrets. The `hermes` user has no sudo and no keys to other hosts: iris is the
# sandbox.
let
  cfg = config.homelab.agent;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;
  voiceTts = config.homelab.voiceTts;

  host = "agent.vanwaaij.com";
  port = 9119;

  # mcp-grafana with the Viewer token read at start, so it stays out of config.yaml.
  grafanaMcp = pkgs.writeShellScript "mcp-grafana-iris" ''
    export GRAFANA_URL=https://grafana.vanwaaij.com
    GRAFANA_SERVICE_ACCOUNT_TOKEN="$(cat ${secretPaths.irisGrafana})"
    export GRAFANA_SERVICE_ACCOUNT_TOKEN
    exec ${pkgs.mcp-grafana}/bin/mcp-grafana "$@"
  '';

  # Headless Claude worker: use the pinned adapter from PATH, never runtime npx.
  # Keep the command name stable so acpx's session scope survives package upgrades.
  # Tool requests are approved without prompts, explicitly authorized for Iris.
  # This is an ACP approval policy, not an OS sandbox or global Claude setting.
  acpxClaude = pkgs.writeShellApplication {
    name = "acpx-claude";
    runtimeInputs = [
      pkgs.acpx
      pkgs.claude-agent-acp
    ];
    text = ''
      exec acpx --agent claude-agent-acp --approve-all "$@"
    '';
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.agent.enable = lib.mkEnableOption "Hermes Agent (Discord bot)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.agent needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    # Make the coding tools available to ordinary shells as well as the service.
    environment.systemPackages = [
      pkgs._1password-cli
      pkgs.acpx
      pkgs.claude-agent-acp
      acpxClaude
    ];

    services.hermes-agent = {
      enable = true;
      container.enable = false;
      user = "hermes";
      group = "hermes";
      stateDir = "/var/lib/hermes";
      # The `hermes` CLI for every shell, with HERMES_HOME pointing at the gateway's
      # state: the logins (`sudo -u hermes -i hermes auth add …`) need it.
      addToSystemPackages = true;

      settings = {
        # Main: Thijs's Claude plan (Anthropic OAuth, logged in by hand: docs/agent.md).
        # Falls back to the ChatGPT plan (Codex OAuth) if Anthropic is unavailable. Both
        # are OAuth logins against a plan allowance, never a pay-per-token API key.
        model = {
          provider = "anthropic";
          default = "claude-sonnet-5-5";
        };
        fallback_providers = [
          {
            provider = "openai-codex";
            model = "gpt-6-sol";
          }
        ];
        # Spoken turns in Discord voice (any MessageType.VOICE turn, see
        # agent/voice_turn_route.py) run on Haiku instead of the main model: a livetalk-style
        # voice session wants instant small talk, not Sonnet/Opus latency, and Hermes falls
        # back to the main model by itself when the conversation no longer fits the cheaper
        # model's context window. `claude-haiku-5-5` is the newest Haiku id this Hermes
        # install's live model catalog knows for the direct `anthropic` provider
        # (`~/.hermes/models_dev_cache.json`, key "anthropic" -> models["claude-haiku-5-5"]:
        # name "Claude Haiku 5.5", release_date 2026-10-07 — newer than the bundled static
        # fallback catalog's `claude-haiku-4-5-20251001`,
        # hermes_cli/models_catalog_static.py's "anthropic" list, which is only a disk-cache-
        # unavailable fallback, not the account's real catalog). `delegation.model` is
        # deliberately left unset: handed-off work (delegate_task) must keep running on
        # whichever model the session/channel it's delegated FROM is already using, not be
        # forced onto Haiku.
        auxiliary.voice_chat = {
          provider = "anthropic";
          model = "claude-haiku-5-5";
        };
        # Behind the router (Traefik, Kanidm gate): the only peer whose forwarded
        # headers count, and the name the dashboard accepts as Host.
        dashboard = {
          public_url = "https://${host}";
          trusted_proxies = [ "10.0.10.110" ];
        };

        # The browser tools: the Chromium Hermes downloads is a generic-Linux binary that
        # NixOS cannot execute (stub-ld, exit 127), so point it at nixpkgs' ungoogled-chromium.
        browser.executable_path = lib.getExe pkgs.ungoogled-chromium;

        # Voice replies in Discord (/voice on or /voice tts): STT via the community
        # ajk0x00/hermes-gemini-stt plugin (Gemini Flash, ~EUR2/mo at Thijs's usage —
        # accepted over free local Whisper for quality; pinned commit, no extra Python
        # deps per its README). GEMINI_API_KEY comes from opnix (secrets.nix), not
        # config.yaml.
        #
        # Project-name mis-transcription ("Orakel" -> "Oracle") is fixed with a
        # vocabulary hint, via our own local-stt-vocab plugin (modules/server/agent/
        # plugins/local-stt-vocab, see docs/agent.md): it seeds a LOCAL file outside
        # the Nix store from its bundled default-vocabulary.md on first use, then on
        # every transcription returns that live file's content as settings.stt.prompt's
        # dynamic counterpart (the pre_transcription hook). Agents edit the live file
        # directly — no PR, no rebuild — Nix only ever supplies the starting default.
        stt = {
          provider = "gemini";
          gemini = {
            model = "gemini-3.8-flash";
            language = "en";
          };
        };
        # Kokoro TTS (English), replacing Edge TTS: an OpenAI-compatible server on
        # prod's GPU via Vulkan (onnxruntime's WebGPU execution provider on the
        # passed-through Arc A380; modules/server/services/voice-tts.nix, docs/agent.md
        # Voice section has the GPU-vs-CPU evidence). `base_url`/`model`/`voice` are
        # Hermes's `tts.openai.*` keys (tools/tts_tool_openai.py in site-packages);
        # `voice` is a Kokoro-FastAPI-style blend ("name(weight)+name(weight)+...",
        # weights optional, normalised to sum to 1) -- the owner's pick over the plain
        # `af_heart` default, 70/30 toward `af_nova`. Any single voice or blend of
        # voices-v1.0.bin's 54 voices is accepted by the server (docs/agent.md Voice
        # section has the syntax), so switching is this one line, not a rebuild of
        # voice-tts.nix. `address`/`port` come from voiceTts (homelab.voiceTts, shared
        # with prod's module — see its comment for why this is a hardcoded literal,
        # not a flake-wide lookup) instead of repeating prod's LAN address here by
        # hand. Dutch (Piper) is deferred.
        tts = {
          provider = "openai";
          openai = {
            base_url = "http://${voiceTts.address}:${toString voiceTts.port}/v1";
            model = "kokoro";
            voice = "af_heart(0.7)+af_nova(0.3)";
            # Kokoro has no auth; the OpenAI SDK still requires a non-empty key. The
            # exact literal Kokoro-FastAPI's own README uses for this — not a secret,
            # never resolved through opnix.
            api_key = "not-needed";
          };
        };
        plugins.enabled = [
          "gemini-stt"
          "local-stt-vocab"
        ];
        # Thijs speaks both Dutch and English in the same voice session; the plugin's
        # default `language_mode: "hint"` sends `stt.gemini.language` above as a fixed hint
        # (verified in the plugin's own source, _payload.py: `if settings.language_mode ==
        # "hint"` gates both the transcribe-model `language_codes` list and the general-model
        # language hint text), which would force every utterance to be read as English.
        # "auto" drops that hint entirely and lets Gemini's own SYSTEM_INSTRUCTION detect the
        # spoken language per utterance (_text.py) — true per-utterance code-switching, one
        # Gemini call, no second STT pass. `stt.gemini.language` above is then inert (kept so
        # a future switch back to "hint" has a sane default); settings live under
        # `plugins.entries.<name>.settings` per the plugin's own _settings.py docstring, not
        # under `stt.gemini.*` (that sub-tree is Hermes's own, read directly by the gateway,
        # not the plugin).
        plugins.entries.gemini-stt.settings.language_mode = "auto";

        # Iris is a coding/ops agent on Discord, not a general assistant: trim the
        # bundled skill catalog down to the agent and software-development ones
        # (plus web's blocked-page-recovery and the creative claude-design skill
        # Thijs still wants) for Discord specifically, so the rest never load
        # into context there.
        skills.platform_disabled.discord = [
          "architecture-diagram"
          "ascii-video"
          "baoyu-infographic"
          "humanizer"
          "manim-video"
          "p5js"
          "popular-web-designs"
          "songwriting-and-ai-music"
          "document-to-action-items"
          "google-workspace"
          "maps"
          "meeting-action-items"
          "microsoft-office"
          "pdf"
          "product-price-monitor"
          "teams-meeting-pipeline"
          "weekly-review-planning"
          "arxiv"
          "competitor-news-monitor"
          "grounded-citations"
          "email-inbox-triage"
          "himalaya"
          "xurl"
          "youtube-content"
          "obsidian"
        ];
      };

      # Plain values (secrets: secrets.nix). Only Thijs; every message, no @mention.
      environment = {
        DISCORD_ALLOWED_USERS = "137629736993030144";
        DISCORD_HOME_CHANNEL = "1569317421251039294";
        DISCORD_REQUIRE_MENTION = "false";
        DISCORD_IGNORE_NO_MENTION = "false";
        # Reply in the channel, not in a new thread per message.
        DISCORD_AUTO_THREAD = "false";
        # Claude Code updates come with `nix flake update`.
        DISABLE_AUTOUPDATER = "1";
      };

      # Claude Code (Thijs's Claude plan, logged in by hand) and Codex for the bundled
      # claude-code / codex skills, plus the basics.
      extraPackages = with pkgs; [
        claude-code
        codex
        _1password-cli
        git
        gh
        jq
        ripgrep
        acpx
        claude-agent-acp
        acpxClaude
      ];

      # Gemini STT (settings.stt above): a directory plugin, pinned to a reviewed commit.
      # No extraPythonPackages needed — its README declares httpx only, already a Hermes
      # core dependency. Declarative install per docs/getting-started/nix-setup.
      #
      # local-stt-vocab is ours (modules/server/agent/plugins/local-stt-vocab): wrapped
      # in a trivial derivation (extraPlugins needs real `package`s — a bare path fails
      # system.build.toplevel's type check, caught the hard way on the builder) since the
      # code lives in this repo, not a separate GitHub one. It bundles its own starting
      # default (default-vocabulary.md) and copies that out to a writable file
      # (plugin_data_dir) the first time it runs — Nix never overwrites that live copy
      # again, so an agent's edits survive every future rebuild.
      extraPlugins = [
        (pkgs.fetchFromGitHub {
          name = "hermes-gemini-stt";
          owner = "ajk0x00";
          repo = "hermes-gemini-stt";
          rev = "e279880389dcdedd5106bd97e390bc8eeb2a88ca";
          hash = "sha256-Dz/BVmKlnwT1rSuRHQdPCZecZpXw0TGGCSw4LMd4hyU=";
        })
        (pkgs.runCommandLocal "local-stt-vocab" { } ''
          cp -r ${./plugins/local-stt-vocab} $out
        '')
      ];

      # Read-only homelab: metrics, logs and alerts through Grafana.
      mcpServers.grafana.command = toString grafanaMcp;

      # The dashboard on the LAN address; the router is the only way in (route.nix).
      backend = {
        mode = "dashboard";
        host = lan.address;
        inherit port;
      };
    };

    # Discord voice channels (/voice join): the bot joined and listened fine
    # (STT still worked) but played nothing back — "Opus codec not found —
    # voice channel playback disabled" in the logs every service start.
    #
    # Root cause (read the actual source, not just the warning text —
    # modules/server/agent/plugins doesn't apply here, this is in the sealed
    # hermes-agent-env venv itself, plugins.platforms.discord.adapter_opus):
    # on Linux it only ever tries `ctypes.util.find_library("opus")`, which
    # shells out to `ldconfig`/`gcc`/`ld` to search. iris has no
    # /etc/ld.so.cache at all (NixOS doesn't maintain one the way
    # Debian/Ubuntu does) and the service's sandboxed PATH doesn't even
    # include those tools — so the probe always returns None and the
    # fallback dlopen is never attempted. A first attempt at fixing this
    # (LD_LIBRARY_PATH alone) did nothing, because that env var is never
    # consulted by this lookup path; only a real dlopen call would see it.
    #
    # A second, much bigger bug found afterwards, still visible in the "it
    # works but nothing happens" symptom (bot joined, heard real audio —
    # "frames ok=313" — but no transcript, no reply at all): every log had
    # `Plugin 'gemini-stt' skipped: requires hermes >=0.22.2, running 0.0.0`
    # — gemini-stt, our ONLY stt.provider, never actually loaded, on any
    # deploy since it was added. `hermes --version`/install-stamp.json's
    # baseVersion is genuinely "0.0.0": this flake input is an unstamped
    # checkout with no git tag history, so the Nix build's install-stamp
    # script couldn't `git describe` and fell back to that placeholder.
    # `git describe` against upstream directly resolves the pinned commit to
    # `v0.23.0+canary...-671-g8c1a9c0b` — comfortably past gemini-stt's
    # ">=0.22.2" gate — so this is a cosmetic Nix-packaging gap, not a real
    # feature gap; patched below rather than waiting on an upstream fix or
    # risking a `nix flake update hermes-agent` across the whole fleet.
    #
    # Fix (both issues, same mechanism): preload/patch before Hermes's own
    # code runs, via a `sitecustomize.py` injected through PYTHONPATH
    # (Python auto-imports it from any directory on sys.path at startup).
    # Doesn't touch the sealed venv itself, just adds a sibling import path.
    # - Opus: calls discord.opus.load_opus(...) directly, so when
    #   adapter_opus.py's load_opus_codec() checks `discord.opus.is_loaded()`
    #   first thing, it's already True and the broken probe is never reached.
    # - Plugin gate: replaces plugins_manifest.running_hermes_version (only
    #   in that module's namespace — hermes --version's own display is
    #   untouched) with the real git-describe-derived version, but ONLY when
    #   the stamped version is still the known-bad "0.0.0" placeholder, so
    #   this self-disables the moment upstream's packaging stamps a real
    #   version correctly.
    systemd.services.hermes-agent.environment.PYTHONPATH = toString (
      pkgs.writeTextDir "sitecustomize.py" ''
        """Preload libopus; fix the plugin requires_hermes version gate.

        Hermes's own opus probe (plugins.platforms.discord.adapter_opus) only
        tries ctypes.util.find_library("opus"), which needs ldconfig/gcc and a
        populated /etc/ld.so.cache — neither exists on this NixOS host. Preload
        it directly here instead, before that probe ever runs.

        Separately: this flake input's install-stamp.json reports
        baseVersion "0.0.0" (no tag history in the fetched tree, so the Nix
        build's `git describe` failed) even though the pinned commit
        (upstream 8c1a9c0b) resolves to v0.23.0+canary...-671 via `git
        describe` run directly against upstream — comfortably past any
        requires_hermes gate a plugin declares today. Without this, every
        requires_hermes-gated plugin (gemini-stt included) is silently
        skipped on load, which is a much bigger bug than it looks: STT
        quietly never worked since that plugin was added, with no error
        surfaced anywhere except a load-time WARNING log line.
        """
        try:
            import discord.opus

            if not discord.opus.is_loaded():
                discord.opus.load_opus("${pkgs.libopus}/lib/libopus.so.0")
        except Exception:
            pass

        try:
            import hermes_cli.plugins_manifest as _pm

            if _pm.running_hermes_version() == "0.0.0":
                _pm.running_hermes_version = lambda: "0.23.0"
        except Exception:
            pass

        # TEMPORARY (docs/agent.md Voice section has the removal note): the owner's voice
        # replies join a live Discord VC (STT works) but nothing is ever spoken back, with
        # zero matching log line in gateway.log or errors.log in any /voice session on
        # record — so the two real TTS gates (_wants_auto_tts / _should_send_voice_reply) and
        # the adapter-side state they read never even reach a warning on the failing path. A
        # harness against these same unmodified classes proves the gates work correctly given
        # the state `/voice join`+`/voice on` are documented to leave behind, so the gap is in
        # the LIVE adapter's actual runtime state (e.g. a reconnect replacing the adapter
        # instance after `/voice on` populated the old one's enabled-chats set) diverging from
        # that documented state — something only a live trace can show. Each wrap below logs
        # one `logger.warning` (prefix "voice-diag:") per call with the real inputs/adapter
        # identity (`id(...)`) and the real decision, then returns/raises exactly what the
        # unmodified original did — proven behavior-preserving in
        # .../cache/scratch/voice-b1/harness.py against the live pinned interpreter (mocks only
        # Discord I/O and the TTS tool). Remove this whole block once that live trace pins the
        # failing condition and the real fix lands.
        try:
            import functools as _voice_diag_functools
            import inspect as _voice_diag_inspect
            import logging as _voice_diag_logging

            from gateway.platforms.event import MessageType as _VoiceDiagMessageType

            def _voice_diag_wrap(cls, attr, logger_, describe):
                """Patch cls.attr: log one logger.warning('voice-diag: ...') per call, built by
                describe(bound_args, result=..., exc=...) from the real inputs and the real
                outcome, then return/raise exactly what the original did. Temporary (see
                docs/agent.md Voice section): remove once the Discord speak-back bug is fixed."""
                raw = cls.__dict__.get(attr)
                is_static = isinstance(raw, staticmethod)
                original = raw.__func__ if is_static else getattr(cls, attr)
                sig = _voice_diag_inspect.signature(original)

                def _bind(args, kwargs):
                    bound = sig.bind(*args, **kwargs)
                    bound.apply_defaults()
                    return bound.arguments

                if _voice_diag_inspect.iscoroutinefunction(original):
                    @_voice_diag_functools.wraps(original)
                    async def wrapper(*args, **kwargs):
                        ba = _bind(args, kwargs)
                        try:
                            result = await original(*args, **kwargs)
                        except Exception as exc:
                            logger_.warning("voice-diag: %s", describe(ba, exc=exc))
                            raise
                        logger_.warning("voice-diag: %s", describe(ba, result=result))
                        return result
                else:
                    @_voice_diag_functools.wraps(original)
                    def wrapper(*args, **kwargs):
                        ba = _bind(args, kwargs)
                        try:
                            result = original(*args, **kwargs)
                        except Exception as exc:
                            logger_.warning("voice-diag: %s", describe(ba, exc=exc))
                            raise
                        logger_.warning("voice-diag: %s", describe(ba, result=result))
                        return result
                setattr(cls, attr, staticmethod(wrapper) if is_static else wrapper)

            def _voice_diag_outcome(result, exc):
                return f"result={result!r}" if exc is None else f"exc={exc!r}"
        except Exception:
            pass

        try:
            import gateway.platforms.base as _voice_diag_base

            def _voice_diag_describe_wants_auto_tts(ba, result=None, exc=None):
                self_, event = ba["self"], ba["event"]
                chat_id = event.source.chat_id
                text_content = ba.get("text_content") or ""
                media_files = ba.get("media_files") or []
                return (
                    f"_wants_auto_tts chat_id={chat_id} message_type={event.message_type} "
                    f"text_len={len(text_content)} media_files={len(media_files)} adapter={id(self_)} "
                    f"chat_enabled={chat_id in self_._auto_tts_enabled_chats} "
                    f"chat_disabled={chat_id in self_._auto_tts_disabled_chats} "
                    f"auto_tts_default={self_._auto_tts_default} {_voice_diag_outcome(result, exc)}"
                )

            _voice_diag_wrap(
                _voice_diag_base.BasePlatformAdapter, "_wants_auto_tts",
                _voice_diag_logging.getLogger("gateway.platforms.base"),
                _voice_diag_describe_wants_auto_tts)
        except Exception:
            pass

        try:
            import gateway.platforms.base as _voice_diag_base

            def _voice_diag_describe_synthesize_auto_tts(ba, result=None, exc=None):
                self_ = ba["self"]
                text_content = ba.get("text_content") or ""
                return (
                    f"_synthesize_auto_tts adapter={id(self_)} text_len={len(text_content)} "
                    f"{_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_base.BasePlatformAdapter, "_synthesize_auto_tts",
                _voice_diag_logging.getLogger("gateway.platforms.base"),
                _voice_diag_describe_synthesize_auto_tts)
        except Exception:
            pass

        try:
            import gateway.platforms.base as _voice_diag_base

            def _voice_diag_describe_play_tts_file(ba, result=None, exc=None):
                self_, event = ba["self"], ba["event"]
                return (
                    f"_play_tts_file chat_id={event.source.chat_id} tts_path={ba.get('tts_path')!r} "
                    f"first={ba.get('first')} adapter={id(self_)} {_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_base.BasePlatformAdapter, "_play_tts_file",
                _voice_diag_logging.getLogger("gateway.platforms.base"),
                _voice_diag_describe_play_tts_file)
        except Exception:
            pass

        try:
            import plugins.platforms.discord.adapter as _voice_diag_discord

            def _voice_diag_describe_discord_play_tts(ba, result=None, exc=None):
                self_, chat_id = ba["self"], ba["chat_id"]
                guild_id = next(
                    (gid for gid, ch in self_._voice_text_channels.items() if str(ch) == str(chat_id)),
                    None)
                in_vc = self_.is_in_voice_channel(guild_id) if guild_id is not None else None
                return (
                    f"play_tts chat_id={chat_id} audio_path={ba.get('audio_path')!r} adapter={id(self_)} "
                    f"guild_id={guild_id} is_in_voice_channel={in_vc} {_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_discord.DiscordAdapter, "play_tts",
                _voice_diag_logging.getLogger("plugins.platforms.discord.adapter"),
                _voice_diag_describe_discord_play_tts)
        except Exception:
            pass

        try:
            import plugins.platforms.discord.adapter as _voice_diag_discord

            def _voice_diag_describe_play_in_voice_channel(ba, result=None, exc=None):
                self_, guild_id = ba["self"], ba["guild_id"]
                return (
                    f"play_in_voice_channel guild_id={guild_id} audio_path={ba.get('audio_path')!r} "
                    f"adapter={id(self_)} is_in_voice_channel={self_.is_in_voice_channel(guild_id)} "
                    f"{_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_discord.DiscordAdapter, "play_in_voice_channel",
                _voice_diag_logging.getLogger("plugins.platforms.discord.adapter"),
                _voice_diag_describe_play_in_voice_channel)
        except Exception:
            pass

        try:
            import gateway.run_voice as _voice_diag_run_voice

            def _voice_diag_describe_should_send_voice_reply(ba, result=None, exc=None):
                self_, event = ba["self"], ba["event"]
                is_voice_input = event.message_type == _VoiceDiagMessageType.VOICE
                voice_mode = self_._voice_mode.get(self_._voice_key_for_source(event.source))
                return (
                    f"_should_send_voice_reply chat_id={event.source.chat_id} "
                    f"is_voice_input={is_voice_input} already_sent={ba.get('already_sent')} "
                    f"voice_mode={voice_mode!r} runner={id(self_)} {_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_run_voice.GatewayVoiceMixin, "_should_send_voice_reply",
                _voice_diag_logging.getLogger("gateway.run"),
                _voice_diag_describe_should_send_voice_reply)
        except Exception:
            pass

        try:
            import gateway.run_voice as _voice_diag_run_voice

            def _voice_diag_describe_toggle_adapter_auto_tts_set(ba, result=None, exc=None):
                adapter, chat_id = ba["adapter"], ba.get("chat_id")
                return (
                    f"_toggle_adapter_auto_tts_set adapter={id(adapter)} chat_id={chat_id!r} "
                    f"on={ba.get('on')} enable={ba.get('enable')} "
                    f"enabled_after={chat_id in getattr(adapter, '_auto_tts_enabled_chats', ())} "
                    f"disabled_after={chat_id in getattr(adapter, '_auto_tts_disabled_chats', ())} "
                    f"{_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_run_voice.GatewayVoiceMixin, "_toggle_adapter_auto_tts_set",
                _voice_diag_logging.getLogger("gateway.run"),
                _voice_diag_describe_toggle_adapter_auto_tts_set)
        except Exception:
            pass

        try:
            import gateway.run_voice as _voice_diag_run_voice

            def _voice_diag_describe_sync_voice_mode_state_to_adapter(ba, result=None, exc=None):
                adapter = ba["adapter"]
                return (
                    f"_sync_voice_mode_state_to_adapter adapter={id(adapter)} "
                    f"enabled={sorted(getattr(adapter, '_auto_tts_enabled_chats', ()))!r} "
                    f"disabled={sorted(getattr(adapter, '_auto_tts_disabled_chats', ()))!r} "
                    f"auto_tts_default={getattr(adapter, '_auto_tts_default', None)} "
                    f"{_voice_diag_outcome(result, exc)}")

            _voice_diag_wrap(
                _voice_diag_run_voice.GatewayVoiceMixin, "_sync_voice_mode_state_to_adapter",
                _voice_diag_logging.getLogger("gateway.run"),
                _voice_diag_describe_sync_voice_mode_state_to_adapter)
        except Exception:
            pass
      ''
    );
  };
}
