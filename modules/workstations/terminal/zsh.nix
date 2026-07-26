{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];
}
// lib.optionalAttrs hostPlatform.isLinux {
  users.defaultUserShell = pkgs.zsh;
}
