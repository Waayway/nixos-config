{ pkgs, lib, isLinux, ... }:
{
  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];
} // lib.optionalAttrs isLinux {
  users.defaultUserShell = pkgs.zsh;
}
