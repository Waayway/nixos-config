{ inputs, ... }:
{
  home.file.".config/rofi/theme.rasi".source = "${inputs.rofiThemeRepo}/tokyonight/tokyonight.rasi";
}
