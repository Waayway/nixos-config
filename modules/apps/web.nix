{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux ({
  programs.firefox = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [ ungoogled-chromium ];
})
