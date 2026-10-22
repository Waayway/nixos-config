{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  # CLI tools that only make sense on macOS.
  config = lib.optionalAttrs hostPlatform.isDarwin {
    environment.systemPackages = with pkgs; [
      coreutils # GNU coreutils (timeout, etc.)
      mas # Mac App Store CLI
      cocoapods
    ];

    homebrew.brews = [ "pdf2image" ];

    # Basecamp CLI (used by the radar workspace's basecamp skill). Not in
    # nixpkgs; shipped as a cask in the official third-party tap.
    homebrew.taps = [
      {
        name = "basecamp/tap";
        trusted = true;
      }
    ];
    homebrew.casks = [ "basecamp/tap/basecamp-cli" ];
  };
}
