{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        python3
        python3Packages.pip
        python3Packages.virtualenv
        uv
      ];
    }

    (lib.optionalAttrs hostPlatform.isDarwin {
      # Libraries for building lxml and xmlsec from source in venvs. Homebrew
      # so the compiled extensions keep stable /opt/homebrew/opt paths.
      homebrew.brews = [
        "libxml2"
        "libxmlsec1"
        "libxslt"
        "pkgconf" # provides pkg-config
      ];

      # libxml2 and libxslt are keg-only (macOS ships its own copies).
      environment.variables.PKG_CONFIG_PATH = [
        "/opt/homebrew/opt/libxml2/lib/pkgconfig"
        "/opt/homebrew/opt/libxslt/lib/pkgconfig"
        "/opt/homebrew/lib/pkgconfig"
      ];
    })
  ];
}
