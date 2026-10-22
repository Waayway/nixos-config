{
  lib,
  hostPlatform,
  ...
}:
{
  # Completion, autosuggestions, syntax highlighting, the shared aliases and
  # the starship prompt come from the system zsh (`modules/common/shell/zsh.nix`).
  programs.zsh = {
    enable = true;
    # The system /etc/zshrc already runs compinit.
    enableCompletion = false;
    shellAliases = {
      sp = "spotify_player";
    };
    initContent = ''
      # Agent shells (Claude Code) don't keep zoxide's chpwd hook, and a
      # fuzzy `cd` there could land in the wrong directory.
      if [[ -z $CLAUDECODE ]]; then
        alias cd=z
      fi

      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word

      export PATH="$HOME/.local/bin:$PATH"
      export PATH="$HOME/.cargo/bin:$PATH"
      export BUN_INSTALL="$HOME/.bun"
      export PATH="$BUN_INSTALL/bin:$PATH"

      export PATH=~/.npm-packages/bin:$PATH
      export NODE_PATH=~/.npm-packages/lib/node_modules
      export PATH=~/develop/flutter/bin:$PATH
    ''
    + lib.optionalString hostPlatform.isDarwin ''

      if [ -f ~/.aliases ]; then
        source ~/.aliases
      fi
    '';

    profileExtra = lib.optionalString hostPlatform.isDarwin ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };
}
