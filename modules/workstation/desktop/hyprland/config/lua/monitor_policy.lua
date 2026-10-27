-- Monitor policy: laptop panel on/off, the primary monitor, and which monitor
-- workspaces live on. Runs inside Hyprland on monitor/lid events; nothing
-- reloads the config or restarts the bar.
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
--   * Workspaces 1-5 on the primary; 6-10 and the named ones on the best other
--     monitor, or on the primary when there's only one.

local M = {}

local MONITOR_KEYS = {
    "mode", "position", "scale", "bitdepth", "cm", "sdr_min_luminance", "sdr_max_luminance",
    "sdrbrightness", "sdrsaturation", "transform", "vrr", "mirror",
}
local NAMED_WORKSPACES = { "󰝚", "󰭹", "󰊴" }

local config
local state = {
    panel_on = nil,
    primary = nil,
    secondary = nil,
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

local function publish(name)
    local dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr"
    local path = dir .. "/primary-monitor"
    local f = io.open(path .. ".tmp", "w")
    if f then
        f:write(name, "\n")
        f:close()
        os.rename(path .. ".tmp", path)
    end
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

local function place_workspaces(primary, secondary)
    local function target(ws)
        if ws.special then
            return nil
        end
        local n = tonumber(ws.name)
        if n and n >= 1 and n <= 5 then
            return primary
        end
        return secondary or primary
    end

    -- Rules for workspaces that don't exist yet.
    for i = 1, 10 do
        hl.workspace_rule({ workspace = tostring(i), monitor = i <= 5 and primary or (secondary or primary) })
    end
    for _, name in ipairs(NAMED_WORKSPACES) do
        hl.workspace_rule({ workspace = "name:" .. name, monitor = secondary or primary })
    end

    -- Move the ones that do.
    for _, ws in ipairs(hl.get_workspaces()) do
        local to = target(ws)
        if to and ws.monitor and ws.monitor.name ~= to then
            local sel = tonumber(ws.name) and ws.id or ("name:" .. ws.name)
            hl.dispatch(hl.dsp.workspace.move({ workspace = sel, monitor = to }))
        end
    end
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
    local secondary = candidates[2] and candidates[2].name or nil

    if primary ~= state.primary then
        publish(primary)
    end
    if primary ~= state.primary or secondary ~= state.secondary then
        state.primary, state.secondary = primary, secondary
        place_workspaces(primary, secondary)
    end
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
