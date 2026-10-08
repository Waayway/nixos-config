{ inputs, lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  home.file.".config/rofi/theme.rasi".source =
    "${inputs.rofiThemeRepo}/tokyonight/tokyonight.rasi";
})
