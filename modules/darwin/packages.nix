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
  };
}
