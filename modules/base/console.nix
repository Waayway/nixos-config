{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) hostPlatform;
in
# The `console.*` options don't exist on nix-darwin, so a `mkIf isLinux`
# guard on the value would still error. Skip the whole module on darwin.
lib.optionalAttrs hostPlatform.isLinux {
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-132n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
  };
}
