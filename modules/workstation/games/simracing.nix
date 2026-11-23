{
  config,
  lib,
  pkgs,
  hostPlatform,
  inputs,
  ...
}:
# Sim racing (`programs.games.simracing.enable`): a Moza wheel on Linux. Boxflat is the
# settings app (firmware, force feedback, rotation) and ships the udev rules that give the
# logged-in user access to the wheel. moza-rev drives the wheel's RPM LED bar from game
# telemetry (UDP on localhost); it is not in nixpkgs, so it is packaged here from a pinned
# commit and run as a user service that idles until a wheelbase is plugged in.
# With the Stream Deck on (`workstation.apps.streamdeck.enable`) the RACING pages press
# buttons on a virtual joystick, served by the companion-buttonbox user service.
# docs/gaming.md has the per-game setup.
let
  moza-rev = pkgs.rustPlatform.buildRustPackage {
    pname = "moza-rev";
    version = "0.1.0-unstable-2026-04-30";

    src = pkgs.fetchFromGitHub {
      owner = "francisdb";
      repo = "moza-rev";
      rev = "6a3cf66c734dde29126e6d9b296adeab4479d005";
      hash = "sha256-/zF2V7NSybU6XqZZeO1NlYWAd+rh6V+JCqil5mgM0WU=";
    };

    cargoHash = "sha256-R6yScvFR8NgNGbZZRlnOjmq9lTGZ8InmxJelKcwe9NY=";

    # serialport finds the wheel through libudev.
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.udev ];

    meta = {
      description = "Drive a Moza Racing wheel's RPM LED bar from game telemetry";
      homepage = "https://github.com/francisdb/moza-rev";
      platforms = lib.platforms.linux;
      mainProgram = "moza-rev";
    };
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.programs.games.simracing = {
    enable = lib.mkEnableOption "Moza sim racing: Boxflat and the moza-rev RPM LED service (modules/workstation/games/simracing.nix)";
  };

  config = lib.mkIf (config.programs.games.simracing.enable && !hostPlatform.isServer) (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.boxflat
          moza-rev
        ];

        # 99-boxflat.rules: uaccess on the Moza devices and /dev/uinput.
        services.udev.packages = [ pkgs.boxflat ];

        # Idles ("no Moza wheelbase found yet") until the wheel is plugged in.
        systemd.user.services.moza-rev = {
          description = "Moza wheel RPM LEDs from game telemetry (moza-rev)";
          wantedBy = [ "default.target" ];
          serviceConfig = {
            ExecStart = lib.getExe moza-rev;
            KillSignal = "SIGINT";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      }

      (lib.mkIf config.workstation.apps.streamdeck.enable {
        # The `buttonbox` Companion module (loaded by streamdeck.nix) sends presses to this
        # daemon's socket; it exposes them as the uinput device "Companion Button Box".
        systemd.user.services.companion-buttonbox = {
          description = "Virtual joystick for the Stream Deck RACING pages";
          wantedBy = [ "default.target" ];
          serviceConfig = {
            ExecStart =
              lib.getExe
                inputs.companion-modules.packages.${pkgs.stdenv.hostPlatform.system}.buttonbox-daemon;
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      })
    ]
  );
}
