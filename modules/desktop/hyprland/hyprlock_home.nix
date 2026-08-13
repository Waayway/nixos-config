{
  pkgs,
  lib,
  isLaptop,
  ...
}:
let
  catpuccinConfig = import ./catpuccin_lib.nix lib;
in
{
  programs.hyprlock = {
    enable = true;
    package = pkgs.hyprlock;
    settings = catpuccinConfig // {
      "$accent" = "$mauve";
      "$accentAlpha" = "$mauveAlpha";
      "$font" = "JetBrainsMono Nerd Font";

      auth = {
        pam = {
          enabled = "true";
        };
        fingerprint = {
          enabled = "true";
        };
      };

      # GENERAL
      general = {
        hide_cursor = "true";
      };

      # BACKGROUND
      background = {
        monitor = "";
        #path = $HOME/.config/background
        blur_passes = 0;
        color = "$base";
      };

      # LAYOUT
      label = [
        {
          monitor = "";
          text = "Layout: $LAYOUT";
          color = "$text";
          font_size = "25";
          font_family = "$font";
          position = "30, -30";
          halign = "left";
          valign = "top";
        }

        # TIME
        {
          monitor = "";
          text = "$TIME";
          color = "$text";
          font_size = "90";
          font_family = "$font";
          position = "-30, 0";
          halign = "right";
          valign = "top";
        }

        # DATE
        {
          monitor = "";
          text = "cmd[update:43200000] date +\"%A, %d %B %Y\"";
          color = "$text";
          font_size = "25";
          font_family = "$font";
          position = "-30, -150";
          halign = "right";
          valign = "top";
        }

        # FINGERPRINT
        (
          if isLaptop then
            {
              monitor = "";
              text = "$FPRINTPROMPT";
              color = "$text";
              font_size = "14";
              font_family = "$font";
              position = "0, -107";
              halign = "center";
              valign = "center";
            }
          else
            { }
        )
      ];

      # INPUT FIELD
      input-field = {
        monitor = "";
        size = "300, 60";
        outline_thickness = "4";
        dots_size = "0.2";
        dots_spacing = "0.2";
        dots_center = "true";
        outer_color = "$accent";
        inner_color = "$surface0";
        font_color = "$text";
        fade_on_empty = "false";
        placeholder_text = "<span foreground=\"##$textAlpha\"><i>󰌾 Logged in as </i><span foreground=\"##$accentAlpha\">$USER</span></span>";
        hide_input = "false";
        check_color = "$accent";
        fail_color = "$red";
        fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
        capslock_color = "$yellow";
        position = "0, -47";
        halign = "center";
        valign = "center";
      };
    };
  };
}
