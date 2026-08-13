{ umport, ... }:
{
  imports = umport {
    paths = [
      ../terminal
      ../programming
    ];
    exclude = [
      # Installed via homebrew cask on darwin; nixpkgs ghostty is
      # marked linux-only in 26.05.
      ../terminal/ghostty_home.nix
    ];
    recursive = true;
    includeHome = true;
  };
}
