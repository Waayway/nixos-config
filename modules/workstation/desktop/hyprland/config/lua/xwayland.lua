-- Draw XWayland windows at the monitor's real pixels instead of stretching a bitmap
-- (blurry on a scaled monitor). Only where the host asks for it: programs.games.steamScale
-- (games/steam-scaling.nix) creates /etc/hypr/xwayland-zero-scaling, together with the
-- Steam setting that makes Steam's interface the right size again. Without that, every
-- XWayland-only program would be tiny, so the laptop does not get this.
-- XWayland is started with the session: it takes a log out and in, not `hyprctl reload`.
--
-- The marker's first line is the scale. X programs (Steam, games outside gamescope) draw
-- their own cursor at XCURSOR_SIZE in real pixels, so it is multiplied by it here, or
-- the cursor is tiny over them. Programs started before a change keep the old size.
local marker = io.open("/etc/hypr/xwayland-zero-scaling", "r")
if marker then
    local scale = tonumber(marker:read("*l") or "") or 1
    marker:close()
    hl.config({
        xwayland = {
            force_zero_scaling = true,
        },
    })
    hl.env("XCURSOR_SIZE", tostring(math.floor(32 * scale + 0.5)))

    -- Steam's interface is Chromium (CEF), which on X11 takes its scale from Xft.dpi.
    -- STEAM_FORCE_DESKTOPUI_SCALING (steam-scaling.nix) is ignored by the 64-bit client
    -- Steam switched to in November 2026, so this is what makes Steam big again. Runs
    -- before autostart.lua's hook (this file is loaded first), so before `steam -silent`.
    local dpi = math.floor(96 * scale + 0.5)
    hl.on("hyprland.start", function()
        hl.exec_cmd("echo 'Xft.dpi: " .. dpi .. "' | xrdb -merge")
    end)
end
