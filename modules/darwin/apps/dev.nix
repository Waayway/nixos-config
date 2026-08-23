{
  pkgs,
  hostPlatform,
  lib,
  upkgs,
  ...
}:
{

  config = lib.optionalAttrs hostPlatform.isDarwin {

    # Code editors + dev tooling GUI apps.
    #
    # vscode builds cleanly on aarch64-darwin via stable nixpkgs.
    # zed-editor pulls livekit-libwebrtc -> ffmpeg 6.1.3 in 25.11, which fails
    # to link against the current Xcode toolchain ("malformed 64-bit
    # a.b.c.d.e version number: -compatibility_version"). Unstable bumps
    # ffmpeg and builds clean, so source zed from there until 25.11 catches up.
    # vscodium / kicad / arduino-ide / Docker Desktop are easier as casks
    # (Docker Desktop in particular is *not* `pkgs.docker`, which is just
    # the CLI engine and won't run on macOS).
    environment.systemPackages = [
      pkgs.vscode
      upkgs.zed-editor
    ];

    homebrew.casks = [
      "vscodium"
      "docker"
      "arduino-ide"
      "kicad"
    ];

  };
}
