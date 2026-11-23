-- Monitor policy: laptop panel on/off, the primary monitor, and where the gaming
-- workspace opens. Runs inside Hyprland on monitor/lid events; nothing reloads the
-- config or restarts the bar.
--
-- Rules:
--   * The laptop panel is on while the lid is open, next to any externals;
--     off only when the lid is closed and an external is enabled. Never off
--     when it's the only one. If it should be on but hasn't come up shortly
--     after (undocking leaves Hyprland with no outputs for a moment, and a
--     runtime monitor rule doesn't always take then), the config is reloaded,
--     which reapplies every monitor rule.
--   * Primary = enabled monitor with the highest `priority` (monitors.lua),
--     ties by left-most, then widest. Written to
--     $XDG_RUNTIME_DIR/hypr/primary-monitor (connector name, e.g. DP-7) and
--     sent as a `custom>>primary>>DP-7` socket2 event; Quickshell reads it.
--     $XDG_RUNTIME_DIR/hypr/primary-monitor-hdr holds 1 when that monitor has
--     `hdr = true` in monitors.lua, else 0; ScopeBuddy's scb.conf
--     (games/scopebuddy_home.nix) starts gamescope with HDR on from it.
--   * No workspace belongs to a monitor: every workspace can be shown on every
--     monitor, and a workspace opens on the monitor you are on. The one default is
--     the gaming workspace, which opens on the primary (large) monitor, where
--     gamescope should be. It is only a default: Super+Shift+Tab (binds.lua) turns the
--     workspaces the monitors show one step around, and a workspace you move stays
--     where you put it.

local M = {}

local MONITOR_KEYS = {
    "mode", "position", "scale", "bitdepth", "cm", "sdr_min_luminance", "sdr_max_luminance",
    "sdrbrightness", "sdrsaturation", "transform", "vrr", "mirror",
}
-- The gaming workspace (rules.lua, Super+G). Its glyph is the same as in rules.lua.
local GAMING_WORKSPACE = "󰊴"

local config
local state = {
    panel_on = nil,
    primary = nil,
    -- output selector -> monitor spec, for every laptop panel we know of
    internal = {},
    pending = false,
    loading = false,
}

local function spec(output, entry, extra)
    local s = { output = output }
    for _, k in ipairs(MONITOR_KEYS) do
        s[k] = entry[k]
    end
    for k, v in pairs(extra or {}) do
        s[k] = v
    end
    return s
end

local function entry_for(m)
    for _, e in ipairs(config.list) do
        if e.desc == m.description then
            return e
        end
    end
end

local function is_internal(m)
    local e = entry_for(m)
    if e then
        return e.internal == true
    end
    return m.name:match("^eDP") ~= nil
end

local function priority(m)
    local e = entry_for(m)
    if e then
        return e.priority or config.unknown_priority
    end
    return is_internal(m) and 10 or config.unknown_priority
end

local function lid_closed()
    for _, lid in ipairs({ "LID0", "LID", "LID1" }) do
        local f = io.open("/proc/acpi/button/lid/" .. lid .. "/state", "r")
        if f then
            local s = f:read("*a")
            f:close()
            return s:match("closed") ~= nil
        end
    end
    return false
end

local function write_file(path, text)
    local f = io.open(path .. ".tmp", "w")
    if f then
        f:write(text, "\n")
        f:close()
        os.rename(path .. ".tmp", path)
    end
end

local function publish(m)
    local dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr"
    local e = entry_for(m)
    -- HDR file first: a reader that sees the new primary also sees its HDR flag.
    write_file(dir .. "/primary-monitor-hdr", (e and e.hdr) and "1" or "0")
    write_file(dir .. "/primary-monitor", m.name)
    local name = m.name
    hl.dispatch(hl.dsp.event("primary>>" .. name))
end

-- Sorted best-first: priority, then left-most, then widest.
local function ranked(monitors)
    table.sort(monitors, function(a, b)
        local pa, pb = priority(a), priority(b)
        if pa ~= pb then
            return pa > pb
        end
        if a.x ~= b.x then
            return a.x < b.x
        end
        return a.width > b.width
    end)
    return monitors
end

-- Where the gaming workspace opens when it does not exist yet: the primary monitor.
-- Nothing is moved: a workspace that is already open stays on the monitor it is on.
local function place_workspaces(primary)
    hl.workspace_rule({ workspace = "name:" .. GAMING_WORKSPACE, monitor = primary })
end

-- With no real output left (undocking with the panel off), Hyprland adds a
-- headless "FALLBACK" output. It must not count as a monitor, or the panel
-- stays off because "an external is still there".
local function is_real(m)
    return m.name ~= "FALLBACK" and not m.name:match("^HEADLESS")
end

function M.refresh()
    state.pending = false
    local enabled = {}
    for _, m in ipairs(hl.get_monitors()) do
        if is_real(m) then
            enabled[#enabled + 1] = m
        end
    end

    local externals = 0
    for _, m in ipairs(enabled) do
        if is_internal(m) then
            if not state.internal[m.name] and not entry_for(m) then
                state.internal[m.name] = spec(m.name, config.fallback)
            end
        else
            externals = externals + 1
        end
    end

    -- Laptop panel.
    local panel_on = externals == 0 or not lid_closed()
    if panel_on ~= state.panel_on then
        state.panel_on = panel_on
        for _, s in pairs(state.internal) do
            hl.monitor(spec(s.output, s, { disabled = not panel_on }))
        end
        if panel_on and next(state.internal) and not state.loading then
            hl.timer(M.ensure_panel, { timeout = 1500, type = "oneshot" })
        end
    end

    -- Primary/secondary among what stays enabled. A panel that's just been
    -- switched on isn't in `enabled` yet; its monitor.added event refreshes again.
    local candidates = {}
    for _, m in ipairs(enabled) do
        if panel_on or not is_internal(m) then
            candidates[#candidates + 1] = m
        end
    end
    if #candidates == 0 then
        return
    end
    ranked(candidates)
    local primary = candidates[1].name

    if primary ~= state.primary then
        state.primary = primary
        publish(candidates[1])
        place_workspaces(primary)
    end
end

-- Super+Shift+Tab: turn the workspaces the monitors show one step around, left to right
-- (the one on the last monitor wraps to the first); `backward` turns the other way. With
-- two monitors that is a plain swap, with three or more it is a rotation, so there is no
-- pair to choose. Built from swap_monitors alone: swapping the first monitor with each of
-- the others in turn rotates forward, and in reverse order rotates backward. Monitors are
-- taken as they are when the key is pressed, so hotplug needs nothing here. Returns false
-- when there is only one monitor.
function M.rotate_workspaces(backward)
    local row = {}
    for _, m in ipairs(hl.get_monitors()) do
        if is_real(m) then
            row[#row + 1] = m
        end
    end
    if #row < 2 then
        return false
    end
    table.sort(row, function(a, b)
        if a.x ~= b.x then
            return a.x < b.x
        end
        return a.y < b.y
    end)
    local first = row[1].name
    local from, to, step = 2, #row, 1
    if backward then
        from, to, step = #row, 2, -1
    end
    for i = from, to, step do
        hl.dispatch(hl.dsp.workspace.swap_monitors({ monitor1 = first, monitor2 = row[i].name }))
    end
    return true
end

-- The panel should be on: if no internal output is enabled by now, reload.
-- Only when an internal panel is actually connected (/sys/class/drm), so a
-- desktop never reloads for a panel it doesn't have.
function M.ensure_panel()
    if not state.panel_on then
        return
    end
    for _, m in ipairs(hl.get_monitors()) do
        if is_real(m) and is_internal(m) then
            return
        end
    end
    local connected = false
    local p = io.popen("cat /sys/class/drm/card*-eDP-*/status 2>/dev/null")
    if p then
        connected = (p:read("*a") or ""):match("^connected") ~= nil
        p:close()
    end
    if not connected then
        return
    end
    -- A reload resets this Lua state, so remember the last one in a file:
    -- at most one per 15 s, never a reload loop.
    local stamp = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr/panel-reload"
    local f = io.open(stamp, "r")
    local last = f and tonumber(f:read("*a")) or 0
    if f then
        f:close()
    end
    if os.time() - last < 15 then
        return
    end
    f = io.open(stamp, "w")
    if f then
        f:write(tostring(os.time()))
        f:close()
    end
    hl.exec_cmd("hyprctl reload")
end

-- Coalesce bursts of events (a dock brings several monitors at once) and let
-- Hyprland finish adding/removing before looking.
local function schedule()
    if state.pending then
        return
    end
    state.pending = true
    hl.timer(M.refresh, { timeout = 250, type = "oneshot" })
end

function M.setup(monitors)
    config = monitors

    hl.monitor(spec("", config.fallback))
    for _, e in ipairs(config.list) do
        hl.monitor(spec("desc:" .. e.desc, e))
        if e.internal then
            state.internal["desc:" .. e.desc] = spec("desc:" .. e.desc, e)
        end
    end

    local here = os.getenv("HOME") .. "/.config/hypr/lua/monitors.local.lua"
    local f = io.open(here, "r")
    if f then
        f:close()
        dofile(here)
    end

    hl.on("hyprland.start", schedule)
    hl.on("monitor.added", schedule)
    hl.on("monitor.removed", schedule)
    -- Lid: decides the panel while an external is connected. Suspend/lock on
    -- lid close stays logind's + hypridle's job (docked: logind ignores the lid).
    hl.bind("switch:on:Lid Switch", schedule, { locked = true })
    hl.bind("switch:off:Lid Switch", schedule, { locked = true })

    -- On a reload, the monitors are already there: apply now so the panel
    -- rule is final before Hyprland applies the new config. (No timers while
    -- loading: the reload is itself what ensure_panel would do.)
    state.loading = true
    M.refresh()
    state.loading = false
end

return M
