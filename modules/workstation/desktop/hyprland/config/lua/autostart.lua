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

        -- Per-host programs: one command per line in /etc/hypr/autostart, written by
        -- workstation.autostart in the host's Nix config (empty on most machines).
        local f = io.open("/etc/hypr/autostart", "r")
        if f then
            for line in f:lines() do
                if line:match("%S") and not line:match("^%s*#") then
                    hl.exec_cmd(line)
                end
            end
            f:close()
        end
    end)
end
