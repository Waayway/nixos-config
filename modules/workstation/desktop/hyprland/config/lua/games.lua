-- Games: tearing, direct scanout and VRR, so a fullscreen game is not composited
-- (and not delayed) by Hyprland's effects. Docs: docs/gaming.md in ~/.flake.
--
-- Hyprland composites every frame unless a single fullscreen window can be scanned out
-- directly (render.direct_scanout, off by default). 2 = only windows whose content type
-- is "game": scanout with native-Wayland Proton outside gamescope gives black screens in
-- some games (hyprwm/Hyprland discussion #14843), so it is limited to the games below,
-- which get `content = "game"` from their rule whether or not they send it themselves.
-- Tearing needs the master switch in look.lua (general.allow_tearing) AND an `immediate`
-- rule per game, which was missing.
-- All three only act on a fullscreen window that is alone on its monitor.
hl.config({
    render = {
        direct_scanout = 2,
    },
    misc = {
        -- Adaptive sync only while something is fullscreen.
        vrr = 2,
    },
})

-- Steam starts Proton games with the class steam_app_<appid>; the nested gamescope window
-- (`scb -- %command%`) is "gamescope". rules.lua puts both on the gaming workspace.
hl.window_rule({
    name = "steam-game-fullscreen",
    match = { class = "^(steam_app_.*)$" },
    immediate = true,
    idle_inhibit = "fullscreen",
    content = "game",
})
hl.window_rule({
    name = "gamescope-fullscreen",
    match = { class = "^(.gamescope-wrapped|gamescope)$" },
    immediate = true,
    idle_inhibit = "fullscreen",
    content = "game",
})
