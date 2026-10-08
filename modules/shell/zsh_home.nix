{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  home.packages = with pkgs; [
    lsd
    bat
    glow
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    shellAliases = {
      ls = "lsd";
      l = "ls -l";
      la = "ls -la";
      ip = "ip --color=auto";
      cat = "bat";
      md = "glow";
      sp = "spotify_player";
    };
    plugins = with pkgs; [
      {
        name = "zsh-syntax-highlighting";
        src = fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "0.6.0";
          sha256 = "0zmq66dzasmr5pwribyh4kbkk23jxbpdw4rjxx0i7dx8jjp2lzl4";
        };
        file = "zsh-syntax-highlighting.zsh";
      }
    ];
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

      export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

      if [ -f ~/.aliases ]; then
        source ~/.aliases
      fi
    '';

    profileExtra = lib.optionalString hostPlatform.isDarwin ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };

  programs.starship = {
    enable = true;
  };

  xdg.configFile."starship.toml".source = ./starship.toml;
}
