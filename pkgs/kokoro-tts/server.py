#!/usr/bin/env python3
"""OpenAI-compatible `/v1/audio/speech` server wrapping Kokoro (kokoro-onnx).

Session providers come from KOKORO_GPU: WebGpuExecutionProvider (Vulkan, via
Dawn) first with CPUExecutionProvider as the per-node fallback for ops WebGPU
doesn't implement, or CPU-only. If WebGPU session init itself raises, this
falls back to a CPU-only session so the bot keeps a voice (logged as a
WARNING, not fatal).

The `voice` field accepts a single name (e.g. "af_heart") or a Kokoro-FastAPI
style blend ("af_heart(0.7)+af_nova(0.3)"; weights optional, missing ones
default to 1 and the whole set is normalised to sum to 1) -- see
_resolve_voice_style.
"""

import io
import json
import logging
import os
import re
import subprocess
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import onnxruntime as ort
from kokoro_onnx import Kokoro
from kokoro_onnx.config import EspeakConfig

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("kokoro-tts")

MODEL_PATH = os.environ["KOKORO_MODEL_PATH"]
VOICES_PATH = os.environ["KOKORO_VOICES_PATH"]
ESPEAK_LIB_PATH = os.environ["ESPEAK_LIB_PATH"]
ESPEAK_DATA_PATH = os.environ["ESPEAK_DATA_PATH"]
HOST = os.environ.get("KOKORO_HOST", "127.0.0.1")
PORT = int(os.environ.get("KOKORO_PORT", "8880"))
USE_GPU = os.environ.get("KOKORO_GPU", "1") not in ("0", "false", "False", "")
DEFAULT_VOICE = os.environ.get("KOKORO_DEFAULT_VOICE", "af_heart")
FFMPEG = os.environ.get("FFMPEG_BIN", "ffmpeg")

SAMPLE_RATE = 24000

# kokoro-onnx phonemizes through plain espeak-ng (phonemizer), not misaki: ja/zh
# voices (jf_*/jm_*, zf_*/zm_*) need misaki's dedicated G2P for good results and
# are not expected to sound right here -- selectable (not rejected), not tuned.
# See thewh1teagle/kokoro-onnx examples/{japanese,chinese}.py (bypass .create()'s
# plain `lang=` path entirely) vs examples/{french,spanish,italian,hindi,
# portuguese}.py (use EspeakG2P with exactly these codes).
LANG_BY_VOICE_PREFIX = {
    "a": "en-us",
    "b": "en-gb",
    "e": "es",
    "f": "fr-fr",
    "h": "hi",
    "i": "it",
    "p": "pt-br",
    "j": "ja",
    "z": "cmn",
}

_inference_lock = threading.Lock()

# Voice blends, Kokoro-FastAPI style: "af_heart(0.7)+af_nova(0.3)". Weights are
# optional per token (missing = 1, so an all-bare blend like "af_heart+af_nova"
# is an equal split); all weights are normalised to sum to 1 regardless. A plain
# single name with no "+" and no "(...)" also matches this (one token, weight 1,
# normalised to 1) and resolves to the exact same style array .create() would
# have used for that name directly -- no behavior change for ordinary requests.
_BLEND_TOKEN_RE = re.compile(r"^([A-Za-z0-9_]+)(?:\(\s*([-+]?[0-9]*\.?[0-9]+)\s*\))?$")
_blend_cache: dict[str, np.ndarray] = {}
_blend_cache_lock = threading.Lock()


class UnknownVoiceError(ValueError):
    def __init__(self, name):
        super().__init__(f"unknown voice {name!r}")
        self.name = name


def _resolve_voice_style(spec: str) -> np.ndarray:
    cached = _blend_cache.get(spec)
    if cached is not None:
        return cached

    names = []
    weights = []
    for token in spec.split("+"):
        match = _BLEND_TOKEN_RE.match(token.strip())
        if not match:
            raise ValueError(f"malformed voice spec {token!r} in {spec!r}")
        name, weight = match.group(1), match.group(2)
        if name not in VOICE_NAMES:
            raise UnknownVoiceError(name)
        names.append(name)
        weights.append(float(weight) if weight is not None else 1.0)

    total = sum(weights)
    if total <= 0:
        raise ValueError(f"voice blend weights must sum to a positive number: {spec!r}")

    blended = sum(
        (w / total) * _kokoro.get_voice_style(n) for w, n in zip(weights, names)
    ).astype(np.float32)

    with _blend_cache_lock:
        _blend_cache[spec] = blended
    return blended


def _build_session():
    providers = ["WebGpuExecutionProvider", "CPUExecutionProvider"] if USE_GPU else ["CPUExecutionProvider"]
    try:
        session = ort.InferenceSession(MODEL_PATH, providers=providers)
    except Exception:
        if not USE_GPU:
            raise
        log.warning("WebGPU session init failed, falling back to CPU-only", exc_info=True)
        session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
    active = session.get_providers()
    if USE_GPU and "WebGpuExecutionProvider" not in active:
        log.warning("WebGPU EP requested but not active (got %s); running on CPU", active)
    else:
        log.info("onnxruntime session active providers: %s", active)
    return session


_session = _build_session()
_kokoro = Kokoro.from_session(
    _session,
    VOICES_PATH,
    espeak_config=EspeakConfig(lib_path=ESPEAK_LIB_PATH, data_path=ESPEAK_DATA_PATH),
)
VOICE_NAMES = sorted(_kokoro.voices.keys())
try:
    _default_voice_style = _resolve_voice_style(DEFAULT_VOICE)
except ValueError as error:
    raise RuntimeError(f"KOKORO_DEFAULT_VOICE={DEFAULT_VOICE!r} is invalid: {error}") from error

# Warm the shader/graph compile cache with one short synth before serving (the
# one-time ~0.8s Dawn/Vulkan shader-pipeline-compile tax w6 measured).
_warm_start = time.monotonic()
with _inference_lock:
    _kokoro.create("Ready.", voice=_default_voice_style, speed=1.0, lang="en-us")
log.info("warmed up in %.2fs, %d voices available", time.monotonic() - _warm_start, len(VOICE_NAMES))


def _lang_for(voice_spec: str) -> str:
    first_name = voice_spec.split("+", 1)[0].split("(", 1)[0].strip()
    return LANG_BY_VOICE_PREFIX.get(first_name[:1], "en-us")


def _pcm_from_floats(samples: np.ndarray) -> bytes:
    clipped = np.clip(samples, -1.0, 1.0)
    return (clipped * 32767.0).astype(np.int16).tobytes()


def _wav_bytes(pcm: bytes) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)
    return buf.getvalue()


def _encode_with_ffmpeg(pcm: bytes, fmt: str) -> bytes:
    proc = subprocess.run(
        [
            FFMPEG,
            "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", "1", "-i", "-",
            "-f", fmt,
            "-",
        ],
        input=pcm,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return proc.stdout


_CONTENT_TYPES = {"mp3": "audio/mpeg", "wav": "audio/wav", "pcm": "audio/pcm", "opus": "audio/opus"}


class Handler(BaseHTTPRequestHandler):
    server_version = "kokoro-tts/1"

    def log_message(self, fmt, *args):
        log.info("%s - %s", self.address_string(), fmt % args)

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "ok", "providers": _session.get_providers()})
        elif self.path == "/v1/audio/voices":
            self._send_json(200, {"voices": VOICE_NAMES})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/audio/speech":
            self._send_json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid JSON"})
            return

        text = payload.get("input")
        if not text:
            self._send_json(400, {"error": "'input' is required"})
            return
        voice_spec = payload.get("voice", DEFAULT_VOICE)
        fmt = payload.get("response_format", "mp3")
        if fmt not in _CONTENT_TYPES:
            self._send_json(400, {"error": f"unsupported response_format {fmt!r}"})
            return

        try:
            voice_style = _resolve_voice_style(voice_spec)
        except UnknownVoiceError as error:
            self._send_json(400, {"error": str(error), "valid_voices": VOICE_NAMES})
            return
        except ValueError as error:
            self._send_json(400, {"error": str(error)})
            return

        try:
            speed = float(payload.get("speed", 1.0))
            with _inference_lock:
                samples, _sr = _kokoro.create(
                    text, voice=voice_style, speed=speed, lang=_lang_for(voice_spec)
                )
        except ValueError as error:
            self._send_json(400, {"error": str(error)})
            return
        except Exception:
            log.exception("synthesis failed")
            self._send_json(500, {"error": "synthesis failed"})
            return

        pcm = _pcm_from_floats(samples)
        if fmt == "pcm":
            audio = pcm
        elif fmt == "wav":
            audio = _wav_bytes(pcm)
        else:
            audio = _encode_with_ffmpeg(pcm, fmt)

        self.send_response(200)
        self.send_header("Content-Type", _CONTENT_TYPES[fmt])
        self.send_header("Content-Length", str(len(audio)))
        self.end_headers()
        self.wfile.write(audio)


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log.info("listening on %s:%s (gpu=%s, default voice=%s)", HOST, PORT, USE_GPU, DEFAULT_VOICE)
    server.serve_forever()


if __name__ == "__main__":
    main()
