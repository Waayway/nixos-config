{
  config,
  pkgs,
  lib,
  hostPlatform,
  ...
}:
# One zsh for every host and every user (root included): completion,
# autosuggestions, syntax highlighting, the aliases and the starship prompt
# live in the system /etc/zshrc. home-manager only adds per-user bits
# (`modules/workstation/shell/zsh_home.nix`).
#
# nix-darwin and NixOS name the zsh plugin options differently, and a
# `mkIf isLinux` on a value still trips the "option doesn't exist" check on
# darwin, so each platform gets its own attrset (like `openssh.nix`).
let
  # In promptInit, not interactiveShellInit: both platforms run
  # interactiveShellInit before promptInit, whose default (`prompt suse`)
  # would replace the starship prompt.
  starshipInit = ''
    if [[ $TERM != "dumb" ]]; then
      eval "$(${lib.getExe pkgs.starship} init zsh)"
    fi
  '';
in
lib.mkMerge [
  {
    programs.zsh.enable = true;
    programs.zsh.enableCompletion = true;
    programs.zsh.promptInit = starshipInit;

    environment.shells = with pkgs; [ zsh ];
    environment.shellAliases = {
      ls = "lsd";
      l = "ls -l";
      la = "ls -la";
      cat = "bat";
      md = "glow";
    };
    environment.systemPackages = with pkgs; [
      lsd
      bat
      glow
      starship
    ];
    environment.etc."starship.toml".source = ./starship.toml;
    environment.variables.STARSHIP_CONFIG = "/etc/starship.toml";
  }
  (
    if hostPlatform.isDarwin then
      {
        programs.zsh.enableAutosuggestions = true;
        programs.zsh.enableSyntaxHighlighting = true;
        # nix-darwin writes `environment.shellAliases` only to /etc/zprofile
        # (login shells); repeat them in /etc/zshrc so non-login interactive
        # shells (zellij panes, a nested `zsh`) get them too.
        programs.zsh.interactiveShellInit = config.system.build.setAliases.text;
      }
    else
      {
        programs.zsh.autosuggestions.enable = true;
        programs.zsh.syntaxHighlighting.enable = true;
        environment.shellAliases.ip = "ip --color=auto";
        users.defaultUserShell = pkgs.zsh;
      }
  )
]
