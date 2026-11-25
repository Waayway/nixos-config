{
  python312,
  python312Packages,
  writeShellApplication,
  ffmpeg,
  espeak-ng,
}:
# Kokoro TTS, OpenAI-compatible `/v1/audio/speech` (server.py), on onnxruntime's
# WebGPU execution provider (Dawn -> Vulkan on Linux) for prod's passed-through
# Arc A380, replacing commit 2's Kokoro-FastAPI CPU container (modules/server/
# services/voice-tts.nix). See w6-report.md (the proven GPU recipe this follows)
# and this directory's own files for the two packaging workarounds it needed:
# onnxruntime-webgpu.nix (the only onnxruntime build in the closure -- "webgpu
# wins") and espeakng-loader-shim.nix (nixpkgs espeak-ng instead of a vendored
# binary wheel).
let
  onnxruntime-webgpu = python312Packages.callPackage ./onnxruntime-webgpu.nix { };
  espeakng-loader-shim = python312Packages.callPackage ./espeakng-loader-shim.nix { };
  kokoro-onnx = python312Packages.callPackage ./kokoro-onnx.nix {
    inherit onnxruntime-webgpu espeakng-loader-shim;
  };
  models = python312Packages.callPackage ./models.nix { };

  # One model instance, one session, loaded by server.py at process startup --
  # not per-request -- so `python312.withPackages` only ever needs to resolve this
  # once per service start, matching the brief's "one model instance loaded at
  # startup" requirement.
  pythonEnv = python312.withPackages (_: [ kokoro-onnx ]);

  server = writeShellApplication {
    name = "kokoro-tts-server";
    runtimeInputs = [
      pythonEnv
      ffmpeg
    ];
    text = ''
      export KOKORO_MODEL_PATH=${models.model}
      export KOKORO_VOICES_PATH=${models.voices}
      export ESPEAK_LIB_PATH=${espeak-ng}/lib/libespeak-ng.so
      export ESPEAK_DATA_PATH=${espeak-ng}/share/espeak-ng-data
      exec python3 ${./server.py} "$@"
    '';
  };
in
server.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit
      models
      kokoro-onnx
      onnxruntime-webgpu
      pythonEnv
      ;
  };
})
