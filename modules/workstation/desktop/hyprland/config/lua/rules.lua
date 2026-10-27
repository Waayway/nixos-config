-- Window rules. Which monitor a workspace lives on is monitor_policy.lua's job.

-- Named workspaces: apps that get their own. The Quickshell bar always shows
-- these (quickshell/config/modules/Workspaces.qml keeps the same list).
hl.window_rule({ name = "spotify-workspace", match = { class = "^(spotify)$" }, workspace = "name:󰝚" })
hl.window_rule({ name = "discord-workspace", match = { class = "^(discord)$" }, workspace = "name:󰭹" })
hl.window_rule({ name = "gamescope-workspace", match = { class = "^(.gamescope-wrapped)$" }, workspace = "name:󰊴" })
