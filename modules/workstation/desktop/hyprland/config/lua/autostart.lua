-- Started once per session. https://wiki.hypr.land/configuring/core/autostart/
-- hypridle/hyprlock/hyprpaper read their .conf files from this folder.
return function(vars)
    hl.on("hyprland.start", function()
        hl.exec_cmd("hypridle")
        hl.exec_cmd("hyprpaper")
        hl.exec_cmd("sleep 1 && bash " .. vars.scripts .. "/wallpaper-random.sh")
        hl.exec_cmd("nm-applet --indicator")
        hl.exec_cmd("qs") -- bar + notifications, ~/.config/quickshell
        hl.exec_cmd("hyprlock")
    end)
end
