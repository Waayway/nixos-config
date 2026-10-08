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
      # Built from source by the formula: needs the full Xcode app (not just
      # the command line tools) installed before this is enabled.
      homebrew.taps = [
        {
          name = "producerguy/tap";
          trusted = true;
        }
      ];
      homebrew.brews = [ "producerguy/tap/thermalforge" ];

      # One-time root setup the formula can't do itself: installs the fan
      # daemon and copies ThermalForge.app to /Applications. Re-run when the
      # brewed version changes (it replaces a stale app bundle).
      system.activationScripts.postActivation.text = ''
        tf=/opt/homebrew/bin/thermalforge
        app=/Applications/ThermalForge.app
        if [ -x "$tf" ]; then
          want="$("$tf" --version 2>/dev/null || true)"
          have="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" 2>/dev/null || true)"
          if [ ! -d "$app" ] || [ "$want" != "$have" ]; then
            echo "setting up ThermalForge..." >&2
            "$tf" install || echo "thermalforge install failed; run 'sudo thermalforge install' by hand" >&2
          fi
        fi
      '';

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
