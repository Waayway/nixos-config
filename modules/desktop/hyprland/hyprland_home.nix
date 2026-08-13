{
  lib,
  ...
}:
let
  inline = lib.generators.mkLuaInline;

  # Keybind helpers. In the Lua config every bind is a single `hl.bind` call
  # (there is no bindm/binde anymore — mouse/repeat are just opts). `keys` and
  # `dispatcher` are raw Lua expressions; `opts` is a normal Nix attrset.
  #   modBind  "SHIFT + N" ''hl.dsp.exec_cmd("x")''           -> $mod + SHIFT + N
  #   keyBind  "XF86AudioPlay" ''hl.dsp.exec_cmd("x")''       -> bare key
  modBind = combo: dispatcher: {
    _args = [
      (inline ''mod .. " + ${combo}"'')
      (inline dispatcher)
    ];
  };
  modBindO = combo: dispatcher: opts: {
    _args = [
      (inline ''mod .. " + ${combo}"'')
      (inline dispatcher)
      opts
    ];
  };
  keyBind = key: dispatcher: {
    _args = [
      key
      (inline dispatcher)
    ];
  };
  keyBindO = key: dispatcher: opts: {
    _args = [
      key
      (inline dispatcher)
      opts
    ];
  };
in
{
  xdg.configFile."hypr/hyprpaper.conf".text =
    "
wallpaper {
    monitor =
    path = ~/.wallpapers
    fit_mode = cover
    timeout = 300
    order = random
    recursive = true
}
";
  wayland.windowManager.hyprland = {
    enable = true;

    # configType defaults to "lua" at stateVersion 26.05, so `settings` below is
    # rendered to ~/.config/hypr/hyprland.lua as hl.* calls. See
    # https://wiki.hypr.land/Configuring/Start/
    settings = {
      # `$mod = SUPER` becomes a Lua local, referenced as `mod .. " + ..."`.
      mod = {
        _var = "SUPER";
      };

      monitor = [
        {
          output = "desc:Acer Technologies X32Q FS 1414012CC3E00";
          mode = "3840x2160@143.98";
          position = "1600x0";
          scale = 2.0;
          bitdepth = 10;
        } # Primary acer 4k 144
        {
          output = "desc:LG Electronics LG ULTRAGEAR 111MAXSP2986";
          mode = "2560x1440@144.0";
          position = "0x90";
          scale = 1.6;
        } # 2nd lg 1440p
        {
          output = "desc:Philips Consumer Electronics Company Philips FTV 0x01010101";
          mode = "3840x2160@120.0";
          position = "1440x0";
          scale = 2.5;
          bitdepth = 10;
        } # Philips tv downstairs
        {
          output = "desc:Nreal Air 2 Pro 0x88888800";
          mode = "1920x1080@120";
          position = "auto";
          scale = 1;
        }
      ];

      env = [
        {
          _args = [
            "HYPRCURSOR_THEME"
            "rose-pine-hyprcursor"
          ];
        }
        {
          _args = [
            "HYPRCURSOR_SIZE"
            "32"
          ];
        }
      ];

      # Autostart. Replaces `exec-once` (which would generate an invalid
      # hl.exec-once(...) call). See https://wiki.hypr.land/Configuring/Basics/Autostart/
      on = {
        _args = [
          "hyprland.start"
          (inline ''
            function()
              hl.exec_cmd("hypridle")
              hl.exec_cmd("hyprpaper")
              hl.exec_cmd("sleep 1 && sh ~/.config/hypr/scripts/wallpaper-random.sh")
              hl.exec_cmd("nm-applet --indicator")
              hl.exec_cmd("eww open bar")
              hl.exec_cmd("hyprlock")
              hl.exec_cmd("hyprland-monitor-attached ~/.config/hypr/scripts/monitor-change.sh")
            end'')
        ];
      };

      # Keyword sections all live under a single hl.config({ ... }) call.
      config = {
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          touchpad = {
            natural_scroll = false;
            scroll_factor = 0.2;
          };
          accel_profile = "flat";
          sensitivity = 0;
        };

        general = {
          gaps_in = 5;
          gaps_out = 20;
          border_size = 2;
          "col.active_border" = {
            colors = [
              "rgba(33ccffee)"
              "rgba(00ff99ee)"
            ];
            angle = 45;
          };
          "col.inactive_border" = "rgba(595959aa)";
          layout = "dwindle";
          allow_tearing = true;
        };

        decoration = {
          rounding = 10;
        };

        dwindle = {
          #pseudotile = true;
          preserve_split = true;
        };

        misc = {
          enable_swallow = true;
          swallow_regex = "^(ghostty)$";
          disable_hyprland_logo = false;
        };
      };

      # Animation curves (old `bezier = name, x0, y0, x1, y1`).
      curve = [
        {
          _args = [
            "myBezier"
            {
              type = "bezier";
              points = [
                [
                  0.05
                  0.9
                ]
                [
                  0.1
                  1.1
                ]
              ];
            }
          ];
        }
        {
          _args = [
            "overshot"
            {
              type = "bezier";
              points = [
                [
                  0.05
                  0.9
                ]
                [
                  0.1
                  1.01
                ]
              ];
            }
          ];
        }
      ];

      # Per-leaf animations (old `animation = name, onoff, speed, curve[, style]`).
      animation = [
        {
          leaf = "windows";
          enabled = true;
          speed = 7;
          bezier = "myBezier";
        }
        {
          leaf = "windowsOut";
          enabled = true;
          speed = 7;
          bezier = "default";
          style = "slide";
        }
        {
          leaf = "windowsIn";
          enabled = true;
          speed = 5;
          bezier = "myBezier";
          style = "slide";
        }
        {
          leaf = "windowsMove";
          enabled = true;
          speed = 5;
          bezier = "default";
        }
        {
          leaf = "border";
          enabled = true;
          speed = 10;
          bezier = "default";
        }
        {
          leaf = "borderangle";
          enabled = true;
          speed = 8;
          bezier = "default";
        }
        {
          leaf = "fade";
          enabled = true;
          speed = 7;
          bezier = "default";
        }
        {
          leaf = "workspaces";
          enabled = true;
          speed = 5;
          bezier = "overshot";
        }
      ];

      window_rule = [
        {
          match = {
            class = "^(spotify)$";
          };
          workspace = "name:󰝚";
        }
        {
          match = {
            class = "^(discord)$";
          };
          workspace = "name:󰭹";
        }
        {
          match = {
            class = "^(.gamescope-wrapped)$";
          };
          workspace = "name:󰊴";
        }
      ];

      bind = [
        (modBind "SHIFT + N" ''hl.dsp.exec_cmd("swaync-client -t -sw")'')
        (modBind "Return" ''hl.dsp.exec_cmd("ghostty")'')
        (modBind "B" ''hl.dsp.exec_cmd("firefox")'')
        (modBind "Space" ''hl.dsp.exec_cmd("rofi -show drun -theme ~/.config/rofi/theme.rasi")'')
        (modBind "T" ''hl.dsp.exec_cmd("nemo")'')

        (modBind "SHIFT + S" ''hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy")'')
        (modBind "ALT + S" ''hl.dsp.exec_cmd("grim -g \"$(slurp)\"")'')
        (modBind "SHIFT + C" ''hl.dsp.exec_cmd("hyprpicker | wl-copy")'')
        (modBind "L" ''hl.dsp.exec_cmd("killall wlogout || wlogout -b 2")'')
        (modBind "SHIFT + L" ''hl.dsp.exec_cmd("killall hyprlock")'')

        (modBind "Q" ''hl.dsp.window.close()'')
        (modBind "V" ''hl.dsp.window.float({ action = "toggle" })'')
        (modBind "P" ''hl.dsp.window.pseudo()'')
        (modBind "J" ''hl.dsp.layout("togglesplit")'')
        (modBind "F" ''hl.dsp.window.fullscreen()'')

        # Move focus with mod + arrow keys
        (modBind "left" ''hl.dsp.focus({ direction = "l" })'')
        (modBind "right" ''hl.dsp.focus({ direction = "r" })'')
        (modBind "up" ''hl.dsp.focus({ direction = "u" })'')
        (modBind "down" ''hl.dsp.focus({ direction = "d" })'')

        # Media controls
        (keyBind "XF86AudioPlay" ''hl.dsp.exec_cmd("playerctl play-pause")'')
        (keyBind "XF86AudioNext" ''hl.dsp.exec_cmd("playerctl next")'')
        (keyBind "XF86AudioPrev" ''hl.dsp.exec_cmd("playerctl previous")'')
        (keyBind "XF86AudioStop" ''hl.dsp.exec_cmd("playerctl stop")'')

        # Mouse: move/resize windows with mod + LMB/RMB drag
        (modBindO "mouse:272" ''hl.dsp.window.drag()'' { mouse = true; })
        (modBindO "mouse:273" ''hl.dsp.window.resize()'' { mouse = true; })

        (modBind "SHIFT + F12" ''hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/wallpaper-random.sh")'')
      ]
      ++ (
        # binds $mod + [SHIFT/ALT +] {1..0} to switch / move-to / move-monitor
        # for workspaces 1..10 (key "0" -> workspace 10).
        builtins.concatLists (
          builtins.genList (
            x:
            let
              n = x + 1;
              ws = builtins.toString (n - ((n / 10) * 10));
            in
            [
              (modBind ws ''hl.dsp.focus({ workspace = ${toString n} })'')
              (modBind "SHIFT + ${ws}" ''hl.dsp.window.move({ workspace = ${toString n} })'')
              (modBind "ALT + ${ws}" ''hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/move_workspace_to_monitor.sh ${toString x}")'')
            ]
          ) 10
        )
      )
      ++ [
        (modBind "S" ''hl.dsp.focus({ workspace = "name:󰝚" })'')
        (modBind "D" ''hl.dsp.focus({ workspace = "name:󰭹" })'')
        (modBind "G" ''hl.dsp.focus({ workspace = "name:󰊴" })'')

        # Volume + brightness (press-and-hold via repeating)
        (keyBindO "XF86AudioRaiseVolume" ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")'' {
          repeating = true;
        })
        (keyBindO "XF86AudioLowerVolume" ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")'' {
          repeating = true;
        })
        (keyBind "XF86AudioMute" ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'')
        (keyBindO "XF86MonBrightnessUp" ''hl.dsp.exec_cmd("brightnessctl s +10%")'' { repeating = true; })
        (keyBindO "XF86MonBrightnessDown" ''hl.dsp.exec_cmd("brightnessctl s 10%-")'' { repeating = true; })
      ];
    };
  };
}
