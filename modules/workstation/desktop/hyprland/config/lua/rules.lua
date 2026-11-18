-- Window rules. Which monitor a workspace lives on is monitor_policy.lua's job.

-- Named workspaces: apps that get their own. The Quickshell bar always shows
-- these (quickshell/config/modules/Workspaces.qml keeps the same list).
hl.window_rule({ name = "spotify-workspace", match = { class = "^(spotify)$" }, workspace = "name:󰝚" })
-- High Tide (TIDAL) starts with the session on hephaestus: `silent` keeps it from taking
-- focus. Its class is its application id.
hl.window_rule({ name = "high-tide-workspace", match = { class = "^(io.github.nokse22.high-tide)$" }, workspace = "name:󰝚 silent" })
hl.window_rule({ name = "discord-workspace", match = { class = "^(discord)$" }, workspace = "name:󰭹" })
-- Only a running game goes to the gaming workspace (monitor_policy.lua keeps it on the
-- primary, large monitor): the nested gamescope window ScopeBuddy opens (`scb -- %command%`
-- in a Steam launch option), or a Proton game started without it (class steam_app_<id>).
-- The Steam client (class `steam`), Heroic and the launchers are not games: they open
-- on whatever workspace you are on, or the one you put them on, e.g. Super+1.
hl.window_rule({ name = "gamescope-workspace", match = { class = "^(gamescope|.gamescope-wrapped)$" }, workspace = "name:󰊴" })
hl.window_rule({ name = "steam-game-workspace", match = { class = "^(steam_app_.*)$" }, workspace = "name:󰊴" })

-- Small utility windows float.
hl.window_rule({ name = "bluetooth-float", match = { class = "^(com.ezratweaver.AdwBluetooth)$" }, float = true })
