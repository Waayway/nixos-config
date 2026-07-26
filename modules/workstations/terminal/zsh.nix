{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv) hostPlatform;
in
{
  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];
}
// lib.optionalAttrs hostPlatform.isLinux {
  users.defaultUserShell = pkgs.zsh;
}
