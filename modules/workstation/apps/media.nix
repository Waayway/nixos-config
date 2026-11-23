args@{
  pkgs,
  lib,
  tools,
  ...
}:
let
  blenderVersion = "5.1.1";
  blenderTarball = pkgs.fetchzip {
    url = "https://download.blender.org/release/Blender${lib.versions.majorMinor blenderVersion}/blender-${blenderVersion}-linux-x64.tar.xz";
    hash = "sha256-y8BMPyM7KYI8rd+12zMIcR9rLM/T1NoqCKJ8o5hxlzg=";
  };
  blenderOfficial = pkgs.buildFHSEnv {
    name = "blender";
    targetPkgs =
      p: with p; [
        libGL
        libsm
        libice
        libx11
        libxext
        libxfixes
        libxi
        libxrender
        libxxf86vm
        libxkbcommon
        wayland
        libdecor
        vulkan-loader
        alsa-lib
        libpulseaudio
        libjack2
        dbus
        fontconfig
        freetype
        zlib
      ];
    runScript = "${blenderTarball}/blender";
    extraInstallCommands = ''
      install -Dm644 ${blenderTarball}/blender.desktop $out/share/applications/blender.desktop
      install -Dm644 ${blenderTarball}/blender.svg $out/share/icons/hicolor/scalable/apps/blender.svg
    '';
  };
in
tools.mkAppCategory args {
  name = "media";
  apps = {
    spotify = {
      linux = [ pkgs.spotify ];
      darwinCasks = [ "spotify" ];
    };
    oxitide = {
      flatpak = [
        {
          flatpakref = "https://flatpak.oxitide.com/oxitide.flatpakref";
          sha256 = "1yhpqlriisy0dvgg53sxmyfsxmvbypf1fz2rpgp0dvhn18fr0346";
        }
      ];
      # No cask; the universal release zip, copied to /Applications/Nix Apps.
      darwinPkgs = [
        (pkgs.stdenvNoCC.mkDerivation rec {
          pname = "oxitide";
          version = "0.2.2";
          src = pkgs.fetchurl {
            url = "https://github.com/yelanxin/OxiTide/releases/download/v${version}/OxiTide-${version}-macos-universal.zip";
            hash = "sha256-p2UcI+hE6GRL9CtgnK4cQzp3307uG4ZUdpK418smuCs=";
          };
          nativeBuildInputs = [ pkgs.unzip ];
          sourceRoot = ".";
          # The zip ships a Finder custom-icon file (Icon) in the bundle root, which
          # breaks the (ad-hoc) code signature check.
          installPhase = ''
            rm -f OxiTide.app/Icon*
            mkdir -p $out/Applications
            cp -R OxiTide.app $out/Applications/
          '';
        })
      ];
    };
    tidal = {
      darwinCasks = [ "tidal" ];
    };
    # TIDAL on Linux: High Tide, a GTK4/libadwaita client (a real toolkit app, not a web
    # view: SONE and tidal-hifi are browsers and lag). Started with the session on
    # hephaestus (workstation.autostart). docs/gaming.md compares the options.
    high-tide.linux = [ pkgs.high-tide ];
    obs = {
      linux = [ pkgs.obs-studio ];
      darwinCasks = [ "obs" ];
    };
    audacity = {
      linux = [ pkgs.audacity ];
      darwinCasks = [ "audacity" ]; # aarch64-darwin nixpkgs build is unreliable
    };
    krita = {
      linux = [ pkgs.krita ];
      darwinCasks = [ "krita" ];
    };
    # Blender's official Linux build, not nixpkgs': nixpkgs' blender links OSL's LLVM 19 and
    # its ROCm build loads ROCm's LLVM 22 as well, and Cycles crashes as soon as it uses HIP
    # (NixOS/nixpkgs#508671). The official build keeps its LLVM to itself and finds HIP at
    # /opt/rocm/hip (hardware/amd-gpu.nix); tested rendering on the RX 9070 XT, HIP and
    # HIP RT. Run in an FHS environment for the few system libraries it does not bundle.
    blender = {
      linux = [ blenderOfficial ];
      darwinCasks = [ "blender" ];
    };
    gimp.linux = [ pkgs.gimp ];
    inkscape.linux = [ pkgs.inkscape ];
    figma.linux = [ pkgs.figma-linux ];
    mpv.linux = [ pkgs.mpv ];
    qbittorrent.linux = [ pkgs.qbittorrent ];
    popsicle.linux = [ pkgs.popsicle ]; # ISO flasher
  };
}
