-- Window rules. Which monitor a workspace lives on is monitor_policy.lua's job.

-- Named workspaces: apps that get their own. The Quickshell bar always shows
-- these (quickshell/config/modules/Workspaces.qml keeps the same list).
hl.window_rule({ name = "spotify-workspace", match = { class = "^(spotify)$" }, workspace = "name:󰝚" })
-- SONE (TIDAL) starts with the session on hephaestus: `silent` keeps it from taking focus.
hl.window_rule({ name = "sone-workspace", match = { class = "^(sone)$" }, workspace = "name:󰝚 silent" })
hl.window_rule({ name = "discord-workspace", match = { class = "^(discord)$" }, workspace = "name:󰭹" })
-- Games get the gaming workspace, which monitor_policy.lua keeps on the primary (large)
-- monitor. Gamescope (the nested window ScopeBuddy opens: `scb -- %command%` in a Steam launch
-- option) goes there, and so does a Proton game that was started without it.
hl.window_rule({ name = "gamescope-workspace", match = { class = "^(gamescope|.gamescope-wrapped)$" }, workspace = "name:󰊴" })
hl.window_rule({ name = "steam-game-workspace", match = { class = "^(steam_app_.*)$" }, workspace = "name:󰊴" })

-- Small utility windows float.
hl.window_rule({ name = "bluetooth-float", match = { class = "^(com.ezratweaver.AdwBluetooth)$" }, float = true })
