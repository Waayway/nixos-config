{
  hostPlatform,
  lib,
  ...
}:
{

  config = lib.optionalAttrs hostPlatform.isDarwin {

    # Browsers + general-purpose comms apps.
    #
    # Firefox and Element ship as casks: their nixpkgs darwin builds are
    # currently flaky on aarch64. Claude desktop is brew-only.
    homebrew.casks = [
      "firefox"
      "element"
      "claude"
    ];
  };
}
