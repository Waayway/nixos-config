{
  lib,
  buildPythonPackage,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  numpy,
  flatbuffers,
  packaging,
  protobuf,
}:
# `onnxruntime-webgpu` (PyPI): a self-contained onnxruntime build with the WebGPU
# execution provider statically linked (Dawn, which dispatches to Vulkan on
# Linux -- w6's report). Installs into the same top-level `onnxruntime/` package
# directory as nixpkgs' plain `onnxruntime` and as `onnxruntime-webgpu`'s own PyPI
# sibling `onnxruntime-ep-webgpu`; this is the only onnxruntime build anywhere in
# this derivation's closure (kokoro-onnx.nix deliberately does not list nixpkgs'
# `onnxruntime` as a dependency -- see its comment), so there is no collision for
# `python3.withPackages` to catch. No manylinux wheel exists upstream for a
# from-source nixpkgs build (Dawn/Vulkan isn't packaged for onnxruntime in
# nixpkgs), so this vendors the published wheel directly, pinned by hash.
buildPythonPackage rec {
  pname = "onnxruntime-webgpu";
  version = "1.27.0";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/24/11/6cd5f840be97819cbd172bacc1868726ab5fa54ceaaa79508c5a64e61233/onnxruntime_webgpu-1.27.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
    hash = "sha256-/l5J4ArXG8ZnMW1XZwv79SVDh4PUo0aODTNzFOyYXL4=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  # The wheel's .so files only declare standard libc/libstdc++ as NEEDED (verified
  # with `patchelf --print-needed`); `libvulkan.so.1` is dlopen'd at runtime
  # (`strings libonnxruntime.so | grep libvulkan` finds the literal), so it is
  # deliberately not here -- the systemd module's LD_LIBRARY_PATH covers that,
  # since autoPatchelfHook can only fix declared NEEDED entries, not dlopen targets.
  buildInputs = [ stdenv.cc.cc.lib ];

  propagatedBuildInputs = [
    numpy
    flatbuffers
    packaging
    protobuf
  ];

  # kokoro-onnx's own resolve_providers() (session.py) only upgrades off CPU for a
  # hardcoded allowlist of distribution names that doesn't include
  # `onnxruntime-webgpu` -- the server builds the InferenceSession manually with
  # `providers=["WebGpuExecutionProvider", "CPUExecutionProvider"]` and
  # `Kokoro.from_session()` instead (w6 workaround 2), so that allowlist gap never
  # bites here.
  pythonImportsCheck = [ "onnxruntime" ];

  meta = {
    description = "ONNX Runtime with the WebGPU execution provider statically linked (Dawn -> Vulkan on Linux)";
    homepage = "https://onnxruntime.ai/docs/execution-providers/WebGPU-ExecutionProvider.html";
    license = lib.licenses.mit;
  };
}
