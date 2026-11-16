# Default STT vocabulary (local-stt-vocab plugin's starting seed)

This is the `local-stt-vocab` plugin's bundled default. It is **not** read
live. On first use the plugin copies it into a writable file outside the Nix
store (`plugin_data_dir("local-stt-vocab")/voice-vocabulary.md`, the real
runtime value) and never touches that copy again — editing this file only
changes what a *fresh* iris starts with.

**To actually change the live vocabulary** (add/remove a term right now, no
PR, no rebuild): edit the live file directly — any agent session on iris can
`write_file`/`patch` it:

```
ls "$HERMES_HOME/plugin-data/local-stt-vocab/voice-vocabulary.md"
```

See `modules/server/agent/plugins/local-stt-vocab/__init__.py` for how it's
used: forwarded to the STT provider (today `gemini-stt`) as a vocabulary hint
alongside every voice message, via Hermes's `pre_transcription` hook, so
project names that would otherwise get mis-transcribed ("Orakel" ->
"Oracle", "Cuetone" -> "Qtone") come through correctly.

Privacy: this text is sent to the configured STT provider with every
transcription. Keep it to names/terms you'd be fine sending there — no
secrets, no session content.

**Format contract (shared with the live file): the last non-blank line is
read verbatim as the prompt.** Keep it on one line, comma-separated.

Hermes, Nous Research, iris, Lodestar, nixos-config, Arcanum, Scaena, Orakel, Cuetone, Kanidm, Discord, GitHub, Tailscale, Proxmox, Hestia, Waayway, Thijs
