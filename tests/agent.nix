# Evaluation check of iris, the Hermes Agent VM (modules/server/agent/,
# docs/plans/2026-11-09-iris-agent-design.md): Hermes on iris only, native mode, its
# state dir and unprivileged user.
{
  pkgs,
  lib,
  nixosConfigurations,
}:
let
  iris = nixosConfigurations.iris.config;
  others = lib.attrNames (lib.removeAttrs nixosConfigurations [ "iris" ]);
  h = iris.services.hermes-agent;
  secrets = iris.services.onepassword-secrets.secrets;
  router = nixosConfigurations.router.config;
  http = router.services.traefik.dynamicConfigOptions.http;
  kanidm = nixosConfigurations.identity.config.homelab.identity.provisionState;
  nas = nixosConfigurations.nixos-manager.config.truenas;
  backup = iris.systemd.services.hermes-backup;
  mount = iris.fileSystems."/var/lib/hermes-backup";
  render = iris.homelab.agent.secretsEnvScript;
  fwRule = "iptables -w -A nixos-fw -p tcp -s 10.0.10.110 --dport 9119 -j nixos-fw-accept";
  prod = nixosConfigurations.prod.config;
  prodPkgs = nixosConfigurations.prod.pkgs;
  voiceTts = prod.homelab.voiceTts;
  voiceTtsService = prod.systemd.services.voice-tts.serviceConfig;
  voiceTtsModels = prodPkgs.kokoro-tts-server.passthru.models;
  voiceTtsFwRule = "iptables -w -A nixos-fw -p tcp -s ${voiceTts.allowFrom} --dport ${toString voiceTts.port} -j nixos-fw-accept";
in
assert iris.networking.hostName == "iris";
assert iris.homelab.agent.enable;
assert iris.services.hermes-agent.enable;
assert !iris.services.hermes-agent.container.enable;
assert iris.services.hermes-agent.stateDir == "/var/lib/hermes";
assert iris.services.hermes-agent.user == "hermes";
assert !(lib.elem "wheel" (iris.users.users.hermes.extraGroups or [ ]));
assert lib.all (n: !nixosConfigurations.${n}.config.services.hermes-agent.enable) others;
# models: Claude plan is primary (Anthropic OAuth); at least one fallback is
# configured, none of it a redundant copy of the primary provider or carrying a
# plaintext key (OAuth plan logins only, docs/agent.md) instead of a device-code login.
assert h.settings.model.provider == "anthropic";
assert lib.isString h.settings.model.default && h.settings.model.default != "";
assert !(h.settings.model ? api_key) && !(h.settings.model ? key_env);
assert h.settings.fallback_providers != [ ];
assert lib.all (f: f.provider != h.settings.model.provider) h.settings.fallback_providers;
assert lib.all (f: !(f ? api_key) && !(f ? key_env)) h.settings.fallback_providers;
# voice replies in Discord (/voice on, /voice tts): STT is the community gemini-stt
# plugin (Gemini Flash, pay-per-use — the one deliberate exception, see secrets.nix).
# The plugin is declared and enabled, and the key is never a plaintext Nix value.
assert h.settings.stt.provider == "gemini";
# TTS: Kokoro on prod's GPU via Vulkan (onnxruntime WebGPU EP, a native systemd
# service -- modules/server/services/voice-tts.nix), not Edge TTS, not a container,
# anymore. Real invariants, not literal echoes: iris's base_url is built from prod's
# own LAN address and the service's own port option (so they can't silently drift
# apart), the service binds that same LAN address and port (not 0.0.0.0 / a
# hand-copied literal), the model+voices files are fixed-output derivations (pinned by
# hash, not "whatever's on disk"), GPU device access is actually granted when `gpu =
# true` (the default), the firewall opens the port to iris's actual LAN address only
# (not the whole LAN interface the way jellyfin.nix/immich.nix's ports are), and the
# key is the server's documented placeholder, so a real key pasted in by mistake fails
# here.
assert h.settings.tts.provider != "edge";
assert h.settings.tts.openai.api_key == "not-needed";
assert prod.homelab.voiceTts.enable;
assert voiceTts.allowFrom == iris.homelab.lan.address;
assert
  h.settings.tts.openai.base_url == "http://${prod.homelab.lan.address}:${toString voiceTts.port}/v1";
assert
  lib.elem "KOKORO_HOST=${prod.homelab.lan.address}" voiceTtsService.Environment
  && lib.elem "KOKORO_PORT=${toString voiceTts.port}" voiceTtsService.Environment;
assert voiceTtsModels.model ? outputHash && voiceTtsModels.voices ? outputHash;
assert
  !voiceTts.gpu
  ||
    voiceTtsService.DeviceAllow == [ "char-drm rw" ]
    &&
      voiceTtsService.SupplementaryGroups == [
        "render"
        "video"
      ];
assert
  !(lib.elem voiceTts.port (
    prod.networking.firewall.interfaces.${prod.homelab.lan.interface}.allowedTCPPorts or [ ]
  ));
assert !(lib.elem voiceTts.port prod.networking.firewall.allowedTCPPorts);
assert lib.hasInfix voiceTtsFwRule prod.networking.firewall.extraCommands;
assert
  h.settings.plugins.enabled != [ ]
  && lib.elem "gemini-stt" h.settings.plugins.enabled
  && lib.elem "local-stt-vocab" h.settings.plugins.enabled;
assert h.extraPlugins != [ ] && lib.any (p: lib.hasInfix "gemini" (lib.getName p)) h.extraPlugins;
assert !(h.settings.stt.gemini ? api_key) && !(h.settings.stt.gemini ? key_env);
# Thijs speaks both Dutch and English in the same voice session: the plugin's own
# config_schema only has two valid language_mode values ("hint"/"auto"; see its
# plugin.yaml), and "hint" is the one that pins every utterance to stt.gemini.language
# — so the real invariant is "not hint", not an echo of "auto" as a bare string.
assert
  let
    languageMode = h.settings.plugins.entries.gemini-stt.settings.language_mode;
  in
  lib.elem languageMode [
    "hint"
    "auto"
  ]
  && languageMode != "hint";
# No static settings.stt.prompt here: the vocabulary hint is dynamic now, supplied
# per-request by local-stt-vocab's pre_transcription hook from a local file outside
# the Nix store (so an agent can edit it without a PR/rebuild). What the Nix build
# CAN check is its own bundled default seed: real content exists, with the expected
# last-line format the plugin's own parser depends on.
assert
  let
    seedLines = builtins.filter (l: l != "") (
      lib.splitString "\n" (
        builtins.readFile ../modules/server/agent/plugins/local-stt-vocab/default-vocabulary.md
      )
    );
  in
  seedLines != [ ] && lib.last seedLines != "";
# Discord voice channels: Hermes's own opus probe (plugins.platforms.discord.
# adapter_opus) only tries ctypes.util.find_library("opus") on Linux, which
# needs ldconfig/gcc and a populated /etc/ld.so.cache — neither exists on
# this host, so it always fails and playback stays silently disabled, even
# though the bot joins and listens fine. Fixed by preloading opus ourselves
# via a sitecustomize.py on PYTHONPATH, checked here by real content, not a
# literal echo: it must actually call discord.opus.load_opus with a libopus
# store path, not just mention "libopus" somewhere.
assert
  let
    pythonPath = iris.systemd.services.hermes-agent.environment.PYTHONPATH or "";
    sitecustomize = if pythonPath == "" then "" else builtins.readFile "${pythonPath}/sitecustomize.py";
  in
  pythonPath != ""
  && lib.hasInfix "discord.opus.load_opus" sitecustomize
  && lib.hasInfix "libopus" sitecustomize
  # The plugin requires_hermes version-gate fix lives in the same file (same
  # mechanism); check it's actually there too, not just the opus half.
  && lib.hasInfix "running_hermes_version" sitecustomize
  && lib.hasInfix "plugins_manifest" sitecustomize;
# Temporary voice-diag block (docs/agent.md Voice section: remove once the Discord
# speak-back bug is fixed). A real structural check, not an echo of a literal: every
# one of the 8 named functions it is supposed to wrap is actually passed to
# _voice_diag_wrap (exactly 8 calls, one per name — catches a deleted/duplicated wrap),
# and the wrapper's defining code both re-raises on exception and returns the original
# result, instead of swallowing either.
assert
  let
    pythonPath = iris.systemd.services.hermes-agent.environment.PYTHONPATH or "";
    sitecustomize = if pythonPath == "" then "" else builtins.readFile "${pythonPath}/sitecustomize.py";
    wrappedNames = [
      "_wants_auto_tts"
      "_synthesize_auto_tts"
      "_play_tts_file"
      "play_tts"
      "play_in_voice_channel"
      "_should_send_voice_reply"
      "_toggle_adapter_auto_tts_set"
      "_sync_voice_mode_state_to_adapter"
    ];
    # One occurrence of "_voice_diag_wrap(" is the helper's own `def`; every other
    # occurrence is a call site, one per wrapped function.
    occurrences = (lib.length (lib.splitString "_voice_diag_wrap(" sitecustomize)) - 1;
    defCount = (lib.length (lib.splitString "def _voice_diag_wrap(" sitecustomize)) - 1;
    callCount = occurrences - defCount;
  in
  lib.hasInfix "voice-diag:" sitecustomize
  && lib.all (name: lib.hasInfix ''"${name}"'' sitecustomize) wrappedNames
  && defCount == 1
  && callCount == lib.length wrappedNames
  && lib.hasInfix "raise" sitecustomize
  && lib.hasInfix "return result" sitecustomize;
assert
  !(h.environment ? ELEVENLABS_API_KEY)
  && !(h.environment ? GROQ_API_KEY)
  && !(h.environment ? VOICE_TOOLS_OPENAI_KEY)
  && !(h.environment ? GEMINI_API_KEY);
# Voice-channel turns run on a cheap/fast model (auxiliary.voice_chat), never a plain
# echo of the literal id: it must stay a *different*, Haiku-family model from the main
# Sonnet/Opus one but the *same* provider (no separate OAuth/API-key setup), and must not
# itself carry a plaintext key (OAuth plan only, like every other model slot here).
# delegation.model/provider stay unset: handed-off work keeps whichever model the
# delegating channel is already using, instead of being forced onto the voice model.
assert h.settings.auxiliary.voice_chat.provider == h.settings.model.provider;
assert h.settings.auxiliary.voice_chat.model != h.settings.model.default;
assert lib.hasInfix "haiku" (lib.toLower h.settings.auxiliary.voice_chat.model);
assert !(h.settings.auxiliary.voice_chat ? api_key) && !(h.settings.auxiliary.voice_chat ? key_env);
assert !(h.settings ? delegation);
assert !(secrets ? irisOpenrouter) && !(lib.hasInfix "OPENROUTER" render);
# Discord: Thijs only, every message, cron output to the home channel
assert h.environment.DISCORD_ALLOWED_USERS == "137629736993030144";
assert h.environment.DISCORD_HOME_CHANNEL == "1569317421251039294";
assert h.environment.DISCORD_REQUIRE_MENTION == "false";
assert h.environment.DISCORD_IGNORE_NO_MENTION == "false";
# replies in the channel itself, no thread per message
assert h.environment.DISCORD_AUTO_THREAD == "false";
assert !(h.environment ? DISCORD_ALLOW_ALL_USERS) && !(h.environment ? GATEWAY_ALLOW_ALL_USERS);
# no pay-per-token keys
assert !(h.environment ? ANTHROPIC_API_KEY) && !(h.environment ? OPENAI_API_KEY);
# secrets: read at unit start from a file rendered in /run (not copied into .env at
# activation, which runs before opnix has fetched them), never the store
assert h.environmentFiles == [ ];
assert lib.all
  (
    u:
    lib.elem "-/run/hermes-secrets/env" (
      lib.toList iris.systemd.services.${u}.serviceConfig.EnvironmentFile
    )
    && lib.elem "opnix-secrets.service" iris.systemd.services.${u}.after
  )
  [
    "hermes-agent"
    "hermes-backend"
  ];
assert lib.all (n: secrets.${n}.owner == "hermes" && secrets.${n}.mode == "0400") [
  "irisDiscord"
  "irisGrafana"
  "irisDashboardPassword"
  "irisDashboardSecret"
  "irisGemini"
];
assert secrets.irisDiscord.reference == "op://Homelab/Iris Discord Bot Token/credential";
assert lib.all (n: secrets ? ${n}) [
  "irisGrafana"
  "irisDashboardPassword"
  "irisDashboardSecret"
  "irisGemini"
];
# tools and the read-only homelab view
assert lib.all (n: lib.any (p: lib.getName p == n) h.extraPackages) [
  "claude-code"
  "codex"
  "git"
  "gh"
  "jq"
  "ripgrep"
  "acpx"
  "claude-agent-acp"
  "acpx-claude"
];
# ACP tools are available to both the gateway and ordinary shells, only on Iris.
assert lib.all (n: lib.any (p: lib.getName p == n) iris.environment.systemPackages) [
  "acpx"
  "claude-agent-acp"
  "acpx-claude"
];
assert lib.all (
  n:
  !(lib.any (
    p:
    lib.elem (lib.getName p) [
      "acpx"
      "acpx-claude"
    ]
  ) nixosConfigurations.${n}.config.environment.systemPackages)
) others;
assert h.environment.DISABLE_AUTOUPDATER == "1";
assert
  h.mcpServers ? grafana
  && !(lib.hasInfix "GRAFANA_SERVICE_ACCOUNT_TOKEN=" (builtins.toJSON h.mcpServers));
# dashboard on the LAN address, behind the router only
assert h.backend.mode == "dashboard" && h.backend.host == "10.0.10.101" && h.backend.port == 9119;
assert h.settings.dashboard.public_url == "https://agent.vanwaaij.com";
assert h.settings.dashboard.trusted_proxies == [ "10.0.10.110" ];
# dashboard route: tailnet only, behind the gate, Thijs only
assert http.services.agent.loadBalancer.servers == [ { url = "http://10.0.10.101:9119"; } ];
assert http.routers.agent-tailnet.rule == "Host(`agent.vanwaaij.com`)";
assert !(http.routers ? agent-public);
assert lib.any (lib.hasSuffix "-gate") http.routers.agent-tailnet.middlewares;
assert router.services.tailscale.serve.services ? agent;
assert kanidm.groups.agent-users.members == [ "thijs" ];
# port 9119 for the router only, not the whole LAN
assert !(lib.elem 9119 (iris.networking.firewall.interfaces.ens18.allowedTCPPorts or [ ]));
assert !(lib.elem 9119 iris.networking.firewall.allowedTCPPorts);
assert lib.hasInfix fwRule iris.networking.firewall.extraCommands;
# nightly state copy to TrueNAS store/internal/iris (snapshot 02:00, restic 02:30)
assert nas.nfsShares.iris.path == "/mnt/store/internal/iris";
assert nas.nfsShares.iris.hosts == [ "10.0.10.101" ];
assert mount.device == "10.0.10.130:/mnt/store/internal/iris";
assert !(lib.any (lib.hasPrefix "x-systemd.idle-timeout") mount.options);
assert iris.users.users.hermes.uid == 950;
assert iris.systemd.timers.hermes-backup.timerConfig.OnCalendar == "*-*-* 01:30";
assert lib.elem "/var/lib/hermes-backup" backup.unitConfig.RequiresMountsFor;
assert backup.serviceConfig.User == "hermes";
# a consistent copy of the SQLite files, not a raw copy of a live database
assert lib.hasInfix ".backup" backup.script && lib.hasInfix "--exclude" backup.script;
# a missing or odd secret stops the render with its name, instead of an empty value
# (or one systemd would unquote) in the env file
assert lib.all (n: lib.hasInfix "need ${n} " render) [
  "DISCORD_BOT_TOKEN"
  "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
  "HERMES_DASHBOARD_BASIC_AUTH_SECRET"
  "GEMINI_API_KEY"
];
assert lib.hasInfix "[ -s " render && lib.hasInfix "A-Za-z0-9" render;
# tar's "file changed as we read it" (exit 1) doesn't fail the night
assert lib.hasInfix "--warning=no-file-changed" backup.script;
assert lib.hasInfix "[ $? -eq 1 ]" backup.script;
# the hermes CLI on PATH for the logins (docs/agent.md), sharing the gateway's state
assert lib.any (p: lib.getName p == "hermes-agent") iris.environment.systemPackages;
assert iris.environment.variables.HERMES_HOME == "/var/lib/hermes/.hermes";
# a change to Hermes's env or config.yaml in Nix restarts both units (Hermes reads them
# only at start; the activation rewrites the files but doesn't restart anything)
assert lib.all
  (
    u:
    lib.any (
      t: lib.hasInfix "DISCORD_AUTO_THREAD" (toString t)
    ) iris.systemd.services.${u}.restartTriggers
    && lib.any (t: lib.hasInfix "public_url" (toString t)) iris.systemd.services.${u}.restartTriggers
  )
  [
    "hermes-agent"
    "hermes-backend"
  ];
pkgs.runCommand "agent" { } "touch $out"
