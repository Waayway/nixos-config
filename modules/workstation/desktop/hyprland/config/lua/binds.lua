-- Every keybind. https://wiki.hypr.land/configuring/core/binds/
return function(vars)
    local function mod(keys)
        return vars.mod .. " + " .. keys
    end
    local exec = hl.dsp.exec_cmd

    -- Apps
    hl.bind(mod("Return"), exec(vars.terminal))
    hl.bind(mod("B"), exec(vars.browser))
    hl.bind(mod("Space"), exec(vars.launcher))
    hl.bind(mod("T"), exec(vars.files))
    hl.bind(mod("SHIFT + N"), exec("qs ipc call notifications toggle"))

    -- Screenshots, colour picker
    hl.bind(mod("SHIFT + S"), exec('grim -g "$(slurp)" - | wl-copy'))
    hl.bind(mod("ALT + S"), exec('grim -g "$(slurp)"'))
    hl.bind(mod("SHIFT + C"), exec("hyprpicker | wl-copy"))

    -- Power menu (Quickshell: lock, logout, suspend, hibernate, reboot, shutdown)
    hl.bind(mod("L"), exec("qs ipc call power toggle"))
    hl.bind(mod("SHIFT + L"), exec("killall hyprlock"))

    -- Windows
    hl.bind(mod("Q"), hl.dsp.window.close())
    hl.bind(mod("V"), hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mod("P"), hl.dsp.window.pseudo())
    hl.bind(mod("J"), hl.dsp.layout("togglesplit"))
    hl.bind(mod("F"), hl.dsp.window.fullscreen())

    hl.bind(mod("left"), hl.dsp.focus({ direction = "left" }))
    hl.bind(mod("right"), hl.dsp.focus({ direction = "right" }))
    hl.bind(mod("up"), hl.dsp.focus({ direction = "up" }))
    hl.bind(mod("down"), hl.dsp.focus({ direction = "down" }))

    hl.bind(mod("mouse:272"), hl.dsp.window.drag(), { mouse = true })
    hl.bind(mod("mouse:273"), hl.dsp.window.resize(), { mouse = true })

    -- Workspaces 1..10 (key 0 = 10): switch, move window, and with ALT move
    -- the current workspace to the Nth monitor counted from the left.
    for i = 1, 10 do
        local key = tostring(i % 10)
        hl.bind(mod(key), hl.dsp.focus({ workspace = i }))
        hl.bind(mod("SHIFT + " .. key), hl.dsp.window.move({ workspace = i }))
        hl.bind(mod("ALT + " .. key), function()
            local monitors = hl.get_monitors()
            table.sort(monitors, function(a, b)
                return a.x < b.x
            end)
            if monitors[i] then
                hl.dispatch(hl.dsp.workspace.move({ monitor = monitors[i].name }))
            end
        end)
    end

    -- Named workspaces (rules.lua)
    hl.bind(mod("S"), hl.dsp.focus({ workspace = "name:󰝚" }))
    hl.bind(mod("D"), hl.dsp.focus({ workspace = "name:󰭹" }))
    hl.bind(mod("G"), hl.dsp.focus({ workspace = "name:󰊴" }))

    -- Media, volume, brightness; `locked` so they work on the lock screen too.
    hl.bind("XF86AudioPlay", exec("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioPause", exec("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioNext", exec("playerctl next"), { locked = true })
    hl.bind("XF86AudioPrev", exec("playerctl previous"), { locked = true })
    hl.bind("XF86AudioStop", exec("playerctl stop"), { locked = true })

    hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
    hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
    hl.bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
    hl.bind("XF86MonBrightnessUp", exec("brightnessctl s +10%"), { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown", exec("brightnessctl s 10%-"), { locked = true, repeating = true })

    -- Wallpaper
    hl.bind(mod("SHIFT + F12"), exec("bash " .. vars.scripts .. "/wallpaper-random.sh"))
end
