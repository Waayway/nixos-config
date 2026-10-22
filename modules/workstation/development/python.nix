{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.mkIf (!hostPlatform.isServer) (
    lib.mkMerge [
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
          "openssl@3" # xmlsec1.pc requires openssl
          "pkgconf" # provides pkg-config
        ];

        # libxml2, libxslt and openssl@3 are keg-only.
        environment.variables.PKG_CONFIG_PATH = [
          "/opt/homebrew/opt/libxml2/lib/pkgconfig"
          "/opt/homebrew/opt/libxslt/lib/pkgconfig"
          "/opt/homebrew/opt/openssl@3/lib/pkgconfig"
          "/opt/homebrew/lib/pkgconfig"
        ];

        # wkhtmltopdf for Odoo PDF reports. Upstream is archived and its only
        # macOS build (patched Qt 0.12.6) is Intel-only, so this takes the
        # x86_64-darwin package and runs it under Rosetta. nixpkgs 26.05 is
        # the last release with x86_64-darwin; revisit when bumping past it.
        environment.systemPackages = [ pkgs.pkgsx86_64Darwin.wkhtmltopdf ];

        # Odoo READMEs expect it in /usr/local/bin.
        system.activationScripts.postActivation.text = ''
          mkdir -p /usr/local/bin
          ln -sfn /run/current-system/sw/bin/wkhtmltopdf /usr/local/bin/wkhtmltopdf
        '';
      })
    ]
  );
}
