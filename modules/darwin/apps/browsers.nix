{
  config,
  hostPlatform,
  lib,
  ...
}:
{
  options.darwin.apps.browsers.enable = lib.mkEnableOption "browser + comms casks";

  config = lib.optionalAttrs hostPlatform.isDarwin (
    lib.mkIf config.darwin.apps.browsers.enable {

      # Browsers + general-purpose comms apps.
      #
      # Firefox and Element ship as casks: their nixpkgs darwin builds are
      # currently flaky on aarch64. Claude desktop is brew-only.
      homebrew.casks = [
        "firefox"
        "element"
        "claude"
      ];
    }
  );
}
