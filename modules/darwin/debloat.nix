{
  config,
  lib,
  hostPlatform,
  user,
  ...
}:
let
  cfg = config.workstation.debloat;

  # Turning the debloat off (or dropping a label from a list) re-enables
  # whatever an earlier switch disabled.
  userAgents = if cfg.enable then cfg.userAgents else [ ];
  systemDaemons = if cfg.enable then cfg.systemDaemons else [ ];
in
{
  options.workstation.debloat = {
    enable = lib.mkEnableOption "disabling unused macOS and vendor background services";

    # Per-user agents (gui/<uid> domain).
    userAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Siri. "Assistant Enabled" = false (defaults.nix) only hides it; the
        # agents still run. siriactionsd and siriappintentsd stay: Shortcuts
        # and App Intents use them.
        "com.apple.campo" # Siri AI.app
        "com.apple.Siri.agent"
        "com.apple.assistantd"
        "com.apple.assistant_service"
        "com.apple.assistant_cdmd"
        "com.apple.siriinferenced"
        "com.apple.siriknowledged"
        "com.apple.sirittsd"
        "com.apple.SiriTTSTrainingAgent"

        # Telemetry and diagnostics.
        "com.apple.analyticsagent"
        "com.apple.DiagnosticsReporter"
        "com.apple.diagnostics_agent"
        "com.apple.diagnosticspushd"
        "com.apple.diagnosticextensionsd"
        "com.apple.geoanalyticsd"
        "com.apple.inputanalyticsd"
        "com.apple.spindump_agent"
        "com.apple.parsec-fbf" # Spotlight/Siri suggestion feedback

        # Screen Time.
        "com.apple.ScreenTimeAgent"
        "com.apple.ScreenTimeSettingsAgent"

        # App Store promos / engagement.
        "com.apple.amsengagementd"

        # Apple Intelligence and suggestions.
        "com.apple.intelligencecontextd"
        "com.apple.intelligenceflowd"
        "com.apple.intelligenceplatformd"
        "com.apple.intelligencetasksd"
        "com.apple.generativeexperiencesd"
        "com.apple.GenerativeFunctions.agentstored"
        "com.apple.privatecloudcomputed"
        "com.apple.callintelligenced"
        "com.apple.visualintelligenced"
        "com.apple.knowledge-agent"
        "com.apple.knowledgeconstructiond"
        "com.apple.spotlightknowledged"
        "com.apple.spotlightknowledged.importer"
        "com.apple.spotlightknowledged.updater"
        "com.apple.suggestd"
        "com.apple.proactiveeventtrackerd"

        # iPhone link: AirDrop, Handoff, Universal Clipboard, Sidecar,
        # iPhone camera, Messages/FaceTime, iPhone sync in Finder.
        "com.apple.sharingd"
        "com.apple.sharing.airdropui"
        "com.apple.rapportd"
        "com.apple.RapportUIAgent"
        "com.apple.companiond"
        "com.apple.coreservices.useractivityd"
        "com.apple.mediacontinuityd"
        "com.apple.cmio.ContinuityCaptureAgent"
        "com.apple.sidecar-display-agent"
        "com.apple.sidecar-relay"
        "com.apple.BTServer.cloudpairing"
        "com.apple.imagent"
        "com.apple.imcore.imtransferagent"
        "com.apple.messagesescrowd"
        "com.apple.facetimemessagestored"
        "com.apple.screensharing.MessagesAgent"
        "com.apple.telephonyutilities.callservicesd"
        "com.apple.AMPDevicesAgent"
        "com.apple.amp.mediasharingd"

        # iCloud and Find My. cloudd, keychain and account daemons stay:
        # sign out of iCloud in System Settings for the rest.
        "com.apple.bird" # iCloud Drive
        "com.apple.cloudphotod"
        "com.apple.cloudsettingssyncagent"
        "com.apple.cksharingmanagementd"
        "com.apple.iCloudNotificationAgent"
        "com.apple.iCloudUserNotificationsd"
        "com.apple.icloudmailagent"
        "com.apple.icloudwebd"
        "com.apple.itunescloudd"
        "com.apple.familycircled"
        "com.apple.findmy.findmylocateagent"
        "com.apple.findmymacmessenger"
        "com.apple.icloud.findmydeviced.findmydevice-user-agent"
        "com.apple.icloud.searchpartyuseragent"

        # Photos analysis, Home, Game Center, News/Stocks/Weather/Tips
        # widgets. photolibraryd stays: apps' photo pickers use it.
        "com.apple.photoanalysisd"
        "com.apple.mediaanalysisd"
        "com.apple.homed"
        "com.apple.homeenergyd"
        "com.apple.gamed"
        "com.apple.GamePolicyAgent"
        "com.apple.newsd"
        "com.apple.weatherd"
        "com.apple.tipsd"
        "com.apple.chronod" # widgets

        # Vendor agents. The apps still work when opened.
        "com.microsoft.teams2.agent"
        "com.elgato.StreamDeck.trampoline"
        "com.microsoft.OneDriveStandaloneUpdater"
        "com.google.keystone.agent"
        "com.google.keystone.xpcservice"
      ];
      description = "launchd labels to disable in the login user's gui domain.";
    };

    # System-wide daemons (system domain).
    systemDaemons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "com.apple.analyticsd"
        "com.apple.audioanalyticsd"
        "com.apple.wifianalyticsd"
        "com.apple.ecosystemanalyticsd"
        "com.apple.SubmitDiagInfo"
        "com.apple.osanalytics.osanalyticshelper"
        "com.apple.spindump"
        "com.apple.tailspind"
        "com.apple.siri.acousticsignature"

        # Find My, Game Mode, iPhone link.
        "com.apple.findmymacd"
        "com.apple.findmymacmessenger"
        "com.apple.icloud.findmydeviced"
        "com.apple.icloud.searchpartyd"
        "com.apple.findmy.findmybeaconingd"
        "com.apple.gamepolicyd"
        "com.apple.rapportd"

        # Vendor updaters. Office licensing stays: Office needs it.
        "com.google.keystone.daemon"
        "com.google.GoogleUpdater.wake.system"
        "com.microsoft.OneDriveStandaloneUpdaterDaemon"
        "com.microsoft.OneDriveUpdaterDaemon"
      ];
      description = "launchd labels to disable in the system domain.";
    };
  };

  config = lib.optionalAttrs hostPlatform.isDarwin {
    # `launchctl disable` is stored by label, so it survives reboots, macOS
    # updates and vendors reinstalling their plists. With SIP on, some Apple
    # jobs can't be booted out of the running session; they stay off after
    # the next reboot. The state files record what we disabled so removed
    # entries get re-enabled.
    system.activationScripts.postActivation.text = ''
      echo "applying launchd debloat..." >&2
      uid="$(id -u -- ${user.name})"
      state=/var/db/nix-darwin-debloat
      mkdir -p "$state"

      debloat() {
        domain="$1" file="$2"
        shift 2
        if [ -f "$file" ]; then
          while IFS= read -r label; do
            case " $* " in
              *" $label "*) ;;
              *) launchctl enable "$domain/$label" 2>/dev/null || true ;;
            esac
          done < "$file"
        fi
        : > "$file"
        for label in "$@"; do
          launchctl disable "$domain/$label" 2>/dev/null || true
          launchctl bootout "$domain/$label" 2>/dev/null || true
          echo "$label" >> "$file"
        done
      }

      debloat "gui/$uid" "$state/user" ${lib.escapeShellArgs userAgents}
      debloat system "$state/system" ${lib.escapeShellArgs systemDaemons}
    '';
  };
}
