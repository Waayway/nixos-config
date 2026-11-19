-- Steam under Hyprland: the main window tiles, everything else Steam opens floats.
-- Steam is an XWayland client with class `steam`; each of its windows has its own title.
-- Static rules (float, center, ...) only look at the title a window has when it opens
-- (initial_title), so the rules below match on that.
--
-- `negative:` inverts a match. The usual copy-pasted `negative:Steam` also keeps "Steam
-- Settings" and "Sign in to Steam" tiled, because those titles contain "Steam"; so the main
-- window is matched by its whole title instead.

-- Everything except the main window: Friends List, chat windows, Settings, Properties,
-- install and update dialogs, "Launching...", notification toasts.
hl.window_rule({
    name = "steam-windows-float",
    match = { initial_class = "^(steam)$", initial_title = "negative:^(Steam|Steam Big Picture Mode)$" },
    float = true,
})

-- The splash Steam shows while a game starts.
hl.window_rule({
    name = "steam-launching-center",
    match = { initial_class = "^(steam)$", initial_title = "^(Launching\\.{3})$" },
    center = true,
})

-- Notification toasts must not take focus from the game or the window you are typing in.
hl.window_rule({
    name = "steam-toast-no-focus",
    match = { initial_class = "^(steam)$", initial_title = "^(notificationtoasts.*)$" },
    no_initial_focus = true,
})

-- XWayland windows with neither class nor title (menu and tooltip helpers that Steam and
-- others open) must not steal focus either. From CachyOS's default Hyprland config.
hl.window_rule({
    name = "xwayland-ghost-no-focus",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
