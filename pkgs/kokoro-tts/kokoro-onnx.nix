{
  lib,
  buildPythonPackage,
  fetchurl,
  hatchling,
  numpy,
  phonemizer,
  onnxruntime-webgpu,
  espeakng-loader-shim,
}:
# thewh1teagle/kokoro-onnx: Kokoro TTS inference over onnxruntime (not the
# PyTorch hexgrad/kokoro nixpkgs already has as `python3Packages.kokoro` -- that
# one can't take an onnxruntime execution provider at all).
buildPythonPackage rec {
  pname = "kokoro-onnx";
  version = "0.6.1";
  pyproject = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/6b/ef/b58dedba0a1417f16352352787fbcfcbaa0b907e284c2ea3ebaf5541109a/kokoro_onnx-0.6.1.tar.gz";
    hash = "sha256-e722bdU3dfcQiKmZmamu/a0kB0Da9UywlBDYux4pTjU=";
  };

  build-system = [ hatchling ];

  # Upstream's own pyproject.toml asks for plain `onnxruntime>=1.20.1` and
  # `espeakng-loader`; neither is listed in propagatedBuildInputs below.
  # `onnxruntime-webgpu` installs the same top-level `onnxruntime` module and must
  # be the only onnxruntime build anywhere `kokoro-onnx` is used -- the Nix-level
  # equivalent of w6's pip workaround 1 ("webgpu wins") -- and espeakng-loader-shim
  # is a different distribution name providing the same module (its own comment).
  # `pythonRuntimeDepsCheckHook` checks distribution *names* and version ranges
  # from the wheel's own metadata regardless of what's actually propagated, so
  # both substitutions, plus phonemizer's version floor (nixpkgs has 3.3.0;
  # upstream asks >=3.4.0 -- the two APIs kokoro-onnx uses,
  # `phonemizer.phonemize()` and `EspeakWrapper.set_data_path/set_library`,
  # predate 3.3.0, and this is proven end to end by the smoke test below, not
  # just assumed), must be told to the check explicitly or it fails the build.
  pythonRemoveDeps = [
    "onnxruntime"
    "espeakng-loader"
  ];
  pythonRelaxDeps = [ "phonemizer" ];

  propagatedBuildInputs = [
    numpy
    phonemizer
    onnxruntime-webgpu
    espeakng-loader-shim
  ];

  pythonImportsCheck = [ "kokoro_onnx" ];
  # Upstream's test suite needs the 353MB model+voices files on disk; not fetched
  # for the build (kokoro-tts/package.nix fetches them separately, for the
  # server to load at its own startup instead).
  doCheck = false;

  meta = {
    description = "TTS with Kokoro and ONNX Runtime";
    homepage = "https://github.com/thewh1teagle/kokoro-onnx";
    license = lib.licenses.mit;
  };
}
