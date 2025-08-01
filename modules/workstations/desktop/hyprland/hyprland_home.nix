{
  lib,
  ...
}:
let
  catpuccinConfig = import ./catpuccin_lib.nix lib;
in
{
  xdg.configFile."hypr/hyprpaper.conf".text = "";
  wayland.windowManager.hyprland = {
    enable = true;

    settings = catpuccinConfig // {
      "$mod" = "SUPER";

      monitor = [
        "desc:Acer Technologies X32Q FS 1414012CC3E00,3840x2160@143.98,1600x0,2.0,bitdepth,10" # Primary acer 4k 144 monitor
        "desc:LG Electronics LG ULTRAGEAR 111MAXSP2986,2560x1440@144.0,0x90,1.6" # 2nd lg 1440p monitor
        "desc:Philips Consumer Electronics Company Philips FTV 0x01010101,3840x2160@120.0,1440x0,2.0,bitdepth,10" # Philips tv downstairs
      ];

      env = [
        "HYPRCURSOR_THEME,rose-pine-hyprcursor"
        "HYPRCURSOR_SIZE,32"
      ];

      exec-once = [
        "hypridle"
        "hyprpaper"
        "sleep 1 && sh ~/.config/hypr/scripts/wallpaper-random.sh"
        "nm-applet --indicator"
        "eww open bar"
        "hyprlock"
        "hyprland-monitor-attached ~/.config/hypr/scripts/monitor-change.sh"
      ];

      bindm = [
        # Move/resize windows with mod + LMB/RMB and dragging
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      workspace = [
        "name:󰝚"
        "name:󰭹"
        "name:󰊴"
      ];

      windowrule = [
        "workspace name:󰝚, class:^(spotify)$"
        "workspace name:󰭹, class:^(discord)$"
        "workspace name:󰊴, class:^(.gamescope-wrapped)$"
      ];

      bind =
        [
          "$mod SHIFT, N, exec, swaync-client -t -sw"
          "$mod, Return, exec, wezterm start --always-new-process"
          "$mod, B, exec, firefox"
          "$mod, Space, exec, rofi -show drun -theme ~/.config/rofi/theme.rasi"
          "$mod, T, exec, nemo"

          "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"
          "$mod ALT, S, exec, grim -g \"$(slurp)\""
          "$mod SHIFT, C, exec, hyprpicker | wl-copy"
          "$mod, L, exec, killall wlogout || wlogout -b 2"
          "$mod SHIFT, L, exec, killall hyprlock"

          "$mod, Q, killactive,"
          "$mod, V, togglefloating,"
          "$mod, P, pseudo"
          "$mod, J, togglesplit"
          "$mod, F, fullscreen"

          # Move focus with mod + arrow keys
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"

          # Media controls
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"
          ", XF86audiostop, exec, playerctl stop"

          "$mod SHIFT, F12, exec, bash ~/.config/hypr/scripts/wallpaper-random.sh"
        ]
        ++ (
          # workspaces
          # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
          builtins.concatLists (
            builtins.genList (
              x:
              let
                ws =
                  let
                    c = (x + 1) / 10;
                  in
                  builtins.toString (x + 1 - (c * 10));
              in
              [
                "$mod, ${ws}, workspace, ${toString (x + 1)}"
                "$mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}"
                "$mod ALT, ${ws}, movecurrentworkspacetomonitor, ${toString x}"
              ]
            ) 10
          )
        )
        ++ [
          "$mod, S, workspace, name:󰝚"
          "$mod, D, workspace, name:󰭹"
          "$mod, G, workspace, name:󰊴"
        ];

      binde = [
        #  Volume + Brightness control
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"

        ", XF86MonBrightnessUp, exec, brightnessctl s +10%"
        ", XF86MonBrightnessDown, exec, brightnessctl s 10%-"
      ];

      input = {
        kb_layout = "us";

        follow_mouse = 1;

        touchpad = {
          natural_scroll = "no";
          scroll_factor = 0.2;
        };

        accel_profile = "flat";
        sensitivity = "0";
      };

      general = {
        gaps_in = 5;
        gaps_out = 20;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";

        layout = "dwindle";
        allow_tearing = "true";
      };

      decoration = {
        rounding = 10;
        # blur {
        #     # blur = yes
        #     # blur_size = 10
        #     # blur_passes ?= 1
        #     # blur_new_optimizations = on
        # }
      };

      animations = {
        enabled = "yes";

        bezier = [
          "myBezier, 0.05, 0.9, 0.1, 1.1"
          "overshot,0.05,0.9,0.1,1.01"
        ];

        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, slide"
          "windowsIn, 1, 5, myBezier, slide"
          "windowsMove, 1, 5, default"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 7, default"
          "workspaces, 1, 5, overshot"
        ];
      };

      dwindle = {
        pseudotile = "yes";
        preserve_split = "yes";
      };

      gestures = {
        workspace_swipe = "on";
      };

      misc = {
        enable_swallow = "true";
        swallow_regex = "^(wezterm)$";
        #swallow_regex = ^(kitty)$
        disable_hyprland_logo = "false";
      };
    };
  };

}
