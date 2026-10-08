args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "ai";
  apps = {
    claude.darwinCasks = [ "claude" ];
    claude-code.darwinCasks = [ "claude-code" ];
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
