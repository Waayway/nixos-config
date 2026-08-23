{
  hostPlatform,
  lib,
  ...
}:
{
  config = lib.optionalAttrs hostPlatform.isDarwin {
    # Pro audio / show-control rig.
    #
    # All casks: REAPER, QLab, Companion, Dante, Wireless Workbench and the
    # Avantis Director are proprietary vendor installers, and Audacity's
    # aarch64-darwin nixpkgs build is unreliable.
    #
    # Manual-only (not on brew, vendor login required or proprietary site):
    #   - Avantis Director (Allen & Heath)
    #   - Dante Virtual Soundcard (Audinate — requires account)
    #   - Dante Activator / Dante Updater (bundled with Controller)
    homebrew.casks = [
      "reaper"
      "qlab"
      "audacity"
      "companion" # Bitfocus Companion
      "dante-controller"
      "wireless-workbench" # Shure WWB
    ];
  };
}
