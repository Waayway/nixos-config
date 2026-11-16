"""local-stt-vocab — a local, agent-editable vocabulary/context hint for STT.

Hermes has a core, static ``settings.stt.prompt`` config key: a vocabulary hint
forwarded to every STT backend (built-in or plugin) alongside the audio, to catch
project names/terms that would otherwise get mis-transcribed ("Orakel" -> "Oracle").
A plain config value means editing it needs a Nix change and a redeploy.

This plugin gives it a *local*, directly-editable counterpart instead, via the
``pre_transcription`` hook (fired before any backend, built-in or plugin — see
Hermes's "Transcription prompt (vocabulary hints)" docs):

1. On first use, it copies its own bundled ``default-vocabulary.md`` (the
   Nix-committed starting default; see that file for the format contract — the
   last non-blank line is the actual term list) into a writable file under
   ``plugin_data_dir()``, *outside* the Nix store.
2. On every transcription after that, it reads the live file's last non-blank
   line fresh and returns it as the ``prompt`` override.

An agent (or Thijs) edits the live file directly with any file tool — no PR, no
rebuild — and the change takes effect on the very next transcription. Nix only
ever supplies the starting point; it never overwrites an existing live file, so
edits survive every future rebuild.
"""

from pathlib import Path

from plugins.plugin_storage import plugin_data_dir

_PLUGIN_NAME = "local-stt-vocab"
_LIVE_FILENAME = "voice-vocabulary.md"
_DEFAULT_SEED = Path(__file__).parent / "default-vocabulary.md"


def live_vocabulary_path() -> Path:
    """The local, writable file agents edit (outside the Nix store)."""
    return plugin_data_dir(_PLUGIN_NAME) / _LIVE_FILENAME


def _last_nonblank_line(text: str) -> str:
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line:
            return line
    return ""


def _ensure_seeded() -> Path:
    path = live_vocabulary_path()
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(_DEFAULT_SEED.read_text(encoding="utf-8"), encoding="utf-8")
    return path


def _on_pre_transcription(
    *,
    file_path=None,
    provider=None,
    model=None,
    language=None,
    prompt=None,
    source=None,
    **kwargs,
):
    # Fail-open per Hermes's hook contract: any error here must leave the
    # transcription request unchanged, never block it.
    try:
        path = _ensure_seeded()
        term_line = _last_nonblank_line(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not term_line:
        return None
    return {"prompt": term_line}


def register(ctx):
    _ensure_seeded()
    ctx.register_hook("pre_transcription", _on_pre_transcription)
