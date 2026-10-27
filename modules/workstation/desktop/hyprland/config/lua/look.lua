-- General layout, decoration and animations.
return function(theme)
    hl.config({
        general = {
            gaps_in = 5,
            gaps_out = 20,
            border_size = 2,
            col = {
                active_border = { colors = { theme.rgba("blue", "ee"), theme.rgba("magenta", "ee") }, angle = 45 },
                inactive_border = theme.rgba("comment", "aa"),
            },
            layout = "dwindle",
            allow_tearing = true,
        },

        decoration = {
            rounding = 10,
        },

        dwindle = {
            preserve_split = true,
        },

        misc = {
            enable_swallow = true,
            swallow_regex = "^(ghostty)$",
            disable_hyprland_logo = false,
        },
    })

    hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })
    hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.01 } } })

    hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "slide" })
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "myBezier", style = "slide" })
    hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "default" })
    hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
    hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
    hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "overshot" })
end
