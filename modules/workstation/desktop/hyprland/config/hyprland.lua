-- Hyprland config, https://wiki.hypr.land/configuring/
--
-- ~/.config/hypr is a link to modules/workstation/desktop/hyprland/config in
-- ~/.flake (hyprland_home.nix). Edit here, then `hyprctl reload`; check
-- `hyprctl configerrors`. No switch needed.
--
-- Files in lua/ are loaded with dofile, not require: require caches modules,
-- dofile re-reads them on every reload.

local dir = os.getenv("HOME") .. "/.config/hypr/lua/"

local function load(name)
    return dofile(dir .. name .. ".lua")
end

local vars = load("vars")
local theme = load("theme")

load("env")
load("look")(theme)
load("input")
load("rules")
load("binds")(vars)
load("monitor_policy").setup(load("monitors"))
load("autostart")(vars)
