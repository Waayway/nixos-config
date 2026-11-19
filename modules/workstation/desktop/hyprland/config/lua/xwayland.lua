-- Draw XWayland windows at the monitor's real pixels instead of stretching a bitmap
-- (blurry on a scaled monitor). Only where the host asks for it: programs.games.steamScale
-- (games/steam-scaling.nix) creates /etc/hypr/xwayland-zero-scaling, together with the
-- Steam setting that makes Steam's interface the right size again. Without that, every
-- XWayland-only program would be tiny, so the laptop does not get this.
-- XWayland is started with the session: it takes a log out and in, not `hyprctl reload`.
local marker = io.open("/etc/hypr/xwayland-zero-scaling", "r")
if marker then
    marker:close()
    hl.config({
        xwayland = {
            force_zero_scaling = true,
        },
    })
end
