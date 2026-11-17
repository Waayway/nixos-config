{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# ScopeBuddy (from Bazzite, now OpenGamingCollective/ScopeBuddy): one command, `scb`, that
# starts gamescope for a game with your default arguments, fixes the Steam overlay and
# Steam Input in nested gamescope, and reads per-game settings. Not in nixpkgs, so it is
# packaged here from the pinned release. The defaults it uses are in scopebuddy_home.nix.
#
# Steam launch option, per game (Steam has no global one): scb -- %command%
let
  scopebuddy = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "scopebuddy";
    version = "1.5.0";

    src = pkgs.fetchFromGitHub {
      owner = "OpenGamingCollective";
      repo = "ScopeBuddy";
      rev = version;
      hash = "sha256-Z4KE6Qs5dcNdoEra1sx69I8EsxztAeVNGgO0ltYz7r0=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      install -Dm755 bin/scopebuddy $out/bin/scopebuddy
      ln -s $out/bin/scopebuddy $out/bin/scb

      # gamescope runs from the store, not from /run/wrappers: a capability wrapper
      # inside Steam's sandbox is a known way to get a game that does not start.
      # mangohud provides `mangoapp` for gamescope's --mangoapp.
      wrapProgram $out/bin/scopebuddy \
        --prefix PATH : ${
          lib.makeBinPath (
            with pkgs;
            [
              gamescope
              xwayland
              perl
              jq
              wlr-randr
              mangohud
            ]
          )
        }
    '';

    meta = {
      description = "Manager script that makes gamescope easier to use on the desktop";
      homepage = "https://github.com/OpenGamingCollective/ScopeBuddy";
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
      mainProgram = "scopebuddy";
    };
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (config.programs.games.enable && !hostPlatform.isServer) {
    environment.systemPackages = [ scopebuddy ];
  };
}
