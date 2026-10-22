args@{ pkgs, tools, ... }:
tools.mkAppCategory args {
  name = "ai";
  apps = {
    claude.darwinCasks = [ "claude" ];
    claude-code.darwinCasks = [ "claude-code" ];
    # Extra Claude Desktop launchers with their own login (work + personal
    # side by side). The brew only installs the command; run `claude-fix`
    # once to create the launchers in ~/Applications.
    claude-fix.darwinConfig = {
      homebrew.taps = [
        {
          name = "sarhej/claude-fix";
          trusted = true;
        }
      ];
      homebrew.brews = [ "sarhej/claude-fix/claude-fix" ];
    };
    opencode = {
      linux = [ pkgs.opencode ];
      darwinPkgs = [ pkgs.opencode ];
      darwinCasks = [ "opencode-desktop" ];
    };
    codex.darwinCasks = [ "codex" ];
    lm-studio.darwinCasks = [ "lm-studio" ];
    ollama.darwinCasks = [ "ollama-app" ];
  };
}
