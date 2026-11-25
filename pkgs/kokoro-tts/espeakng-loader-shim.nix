{
  buildPythonPackage,
  python,
  writeText,
  espeak-ng,
}:
# kokoro-onnx's tokenizer.py unconditionally does `import espeakng_loader` and
# falls back to its `get_library_path()`/`get_data_path()` only when no explicit
# `EspeakConfig` is given (kokoro-tts's server.py always gives one, pointing at
# nixpkgs' own `espeak-ng`). Rather than vendor the real PyPI `espeakng-loader`
# wheel -- which bundles its own prebuilt `libespeak-ng.so` + a full copy of
# espeak-ng-data (10MB, a second build of the same library already in this
# closure) -- this is a 3-line stand-in exposing the same two functions over
# nixpkgs' `espeak-ng`. nixpkgs' own `python3Packages.phonemizer` patches in this
# exact same path as its auto-detect default (`backend-paths.patch`, citing
# espeakng-loader's own "Usage with phonemizer" docs for precisely this
# nixpkgs/non-vendored case) -- this shim follows the same precedent for the one
# function kokoro-onnx calls that phonemizer's patch doesn't cover.
let
  initPy = writeText "espeakng_loader_init.py" ''
    def get_library_path():
        return "${espeak-ng}/lib/libespeak-ng.so"


    def get_data_path():
        return "${espeak-ng}/share/espeak-ng-data"
  '';
in
buildPythonPackage {
  pname = "espeakng-loader-shim";
  version = "0";
  format = "other";
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/${python.sitePackages}/espeakng_loader"
    cp ${initPy} "$out/${python.sitePackages}/espeakng_loader/__init__.py"
    runHook postInstall
  '';

  meta = {
    description = "Local stand-in for PyPI's espeakng-loader, pointing at nixpkgs' espeak-ng instead of a vendored binary";
  };
}
