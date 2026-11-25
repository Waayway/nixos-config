{ fetchurl }:
# thewh1teagle/kokoro-onnx release model-files-v1.1 (the fp32 English/multilingual
# export + its voice pack; not the fp16/int8 variants, and not the -zh model/voices,
# which are for the dedicated Chinese export this server doesn't use).
{
  model = fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.onnx";
    hash = "sha256-vrDRhI3umknaOSzD3yaVjUbPo10yHt9DT1KUkVPw3zo=";
  };
  voices = fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin";
    hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
  };
}
