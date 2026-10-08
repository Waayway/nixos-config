{
  config,
  lib,
  hostPlatform,
  ...
}:
{
  options.hardware.thermalforge.enable = lib.mkEnableOption "ThermalForge fan control (macOS)";

  config = lib.optionalAttrs hostPlatform.isDarwin (
    lib.mkIf config.hardware.thermalforge.enable {
      homebrew.taps = [ "producerguy/tap" ];
      homebrew.brews = [ "producerguy/tap/thermalforge" ];

      # Start it at login.
      launchd.user.agents.thermalforge.serviceConfig = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "ThermalForge"
        ];
        RunAtLoad = true;
      };
    }
  );
}
