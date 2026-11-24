-- Draw XWayland windows at the monitor's real pixels instead of stretching a bitmap
-- (blurry on a scaled monitor). Only where the host asks for it: programs.games.steamScale
-- (games/steam-scaling.nix) creates /etc/hypr/xwayland-zero-scaling, together with the
-- Steam setting that makes Steam's interface the right size again. Without that, every
-- XWayland-only program would be tiny, so the laptop does not get this.
-- XWayland is started with the session: it takes a log out and in, not `hyprctl reload`.
--
-- The marker's first line is the scale (used for Xft.dpi below). XCURSOR_SIZE stays 32
-- (env.lua): force_zero_scaling does not reach the cursor. Xwayland's cursor surface has
-- buffer scale 1, so Hyprland draws it at XCURSOR_SIZE x the monitor's scale, just like
-- the native cursor. Multiplying it here made a 64 px X cursor drawn at 128 px into the
-- RX 9070's 64x64 cursor plane (DRM_CAP_CURSOR_WIDTH): only its top-left part showed.
-- Hyprland checks the buffer size against the plane, not the drawn size, so it does not
-- fall back to a software cursor for this.
--
-- Keeping XCURSOR_SIZE at 32 is not enough: Steam (Chromium) multiplies it by its own
-- scale from Xft.dpi below and hands Xwayland a 64 px cursor ("Caching cursor image ...
-- size 64x64" in the journal), which Hyprland again draws at 128 px. So with the marker
-- the cursor is drawn in software, where any size fits.
local marker = io.open("/etc/hypr/xwayland-zero-scaling", "r")
if marker then
    local scale = tonumber(marker:read("*l") or "") or 1
    marker:close()
    hl.config({
        xwayland = {
            force_zero_scaling = true,
        },
        cursor = {
            no_hardware_cursors = 1,
        },
    })

    -- Steam's interface is Chromium (CEF), which on X11 takes its scale from Xft.dpi.
    -- STEAM_FORCE_DESKTOPUI_SCALING (steam-scaling.nix) is ignored by the 64-bit client
    -- Steam switched to in November 2026, so this is what makes Steam big again. Runs
    -- before autostart.lua's hook (this file is loaded first), so before `steam -silent`.
    local dpi = math.floor(96 * scale + 0.5)
    hl.on("hyprland.start", function()
        hl.exec_cmd("echo 'Xft.dpi: " .. dpi .. "' | xrdb -merge")
    end)
end
