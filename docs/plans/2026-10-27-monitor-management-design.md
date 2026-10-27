# Monitor management: design

Status: implemented 2026-10-27 (hermes). Steps: `2026-10-27-monitor-management-plan.md`.
Builds on `2026-10-27-hyprland-lua-quickshell-design.md`.

## How it works today, and what's wrong

- Monitor definitions live in two places: the four `monitor` entries in the
  old Nix config, and Monique's `~/.config/hypr/monitors.lua` (outside the repo).
- `hyprland-monitor-attached` (an extra daemon) runs `monitor-change.sh` on
  every hotplug. That script:
  - runs `hyprctl reload`: re-applies the whole config, every hotplug;
  - checks `[ $MONITORS == "eDP-1" ]` unquoted: with two monitors this is a
    shell syntax error, with one external and the panel it falls through;
  - disables the panel by port name (`eDP-1`), while Monique uses its
    description (`BOE NE135A1M-NY1`);
  - does `eww kill && eww open bar`. The bar is restarted mid-hotplug while
    the monitor list is changing, and is only ever on `:monitor 0` (whatever
    index that is at the moment). This is the crash.
- `SUPER+ALT+N` moves a workspace to `hyprctl monitors -j` index N-1, which is
  connection order, not left-to-right.

## Design

1. **One monitor table in the repo**, `hyprland/config/lua/monitors.lua`, keyed
   by description (stable across ports and docks), pure data:
   ```lua
   return {
     acer   = { desc = "Acer Technologies X32Q FS 1414012CC3E00", mode = "3840x2160@143.98", position = "1600x0", scale = 2,   bitdepth = 10 },
     lg     = { desc = "LG Electronics LG ULTRAGEAR 111MAXSP2986", mode = "2560x1440@144",   position = "0x90",   scale = 1.6 },
     tv     = { desc = "Philips Consumer Electronics Company Philips FTV 0x01010101", mode = "3840x2160@120", position = "1440x0", scale = 2.5, bitdepth = 10, cm = "srgb", sdr_min_luminance = 0.2, sdr_max_luminance = 80 },
     nreal  = { desc = "Nreal Air 2 Pro 0x88888800", mode = "1920x1080@120", position = "auto", scale = 1 },
     laptop = { desc = "BOE NE135A1M-NY1", internal = true },
   }
   ```
   plus a catch-all `{ output = "", mode = "preferred", position = "auto", scale = "auto" }`
   for anything unknown. The Monique settings (TV colour management) are merged in.
2. **Policy in Lua, inside Hyprland**: `monitor_policy.lua` subscribes to
   `hl.on("monitor.added")`, `hl.on("monitor.removed")` and the lid switch, and
   calls `hl.monitor{}` for just the panel. No external daemon, no
   `hyprctl reload`, no script. The rule is the old intent, written down:
   - panel **on** while the lid is open, next to any externals;
   - panel **off** only when the lid is closed and an external is connected
     (changed 2026-10-27 from "off with any external": undocking then left a
     gap with no screen at all);
   - if the panel should be on but isn't up 1.5 s later (Hyprland briefly has
     no outputs when a dock goes away, and a runtime monitor rule doesn't
     always take then), `hyprctl reload`, at most once per 15 s;
   - never disable the last enabled output (safety: if `hl.get_monitors()` would
     be empty, keep the panel on).
3. **Primary monitor.** Hyprland has no such thing, so the policy defines one:
   - Every entry in the table has a `priority` (acer 100, tv 90, nreal 80,
     lg 50, laptop 10). The primary is the **enabled** output with the
     highest priority. Unknown screens rank 20 (above the panel, below known
     externals); ties go to the left-most (`x`), then the larger.
   - It's recomputed in `refresh()`, i.e. on start, on add/remove and on lid
     changes, after the panel has been switched on/off.
   - It's **published** to `$XDG_RUNTIME_DIR/hypr/primary-monitor` as the
     output's connector name (`DP-2`), written atomically (write `.tmp`, rename)
     with Lua's `io`/`os`, which Hyprland's Lua has (checked on hermes). It's
     also sent as a custom event (`hl.dsp.event("primary>>DP-2")`) for anything
     listening on socket2.
   - The file survives Quickshell restarts and is there before Quickshell
     starts, so there is no startup race.
   Users of the primary: the Quickshell bar and notification popups,
   workspaces 1-5 (below), the cursor/focus at session start.
4. **The bar never restarts.** Quickshell has one `PanelWindow` with
   `screen: primaryScreen`, where `primaryScreen` is the entry of
   `Quickshell.screens` whose `name` matches the file (read with
   `FileView { watchChanges: true }`), falling back to `Quickshell.screens[0]`
   while the file is missing or names a screen Quickshell doesn't have yet.
   A change of primary just moves the window. Nothing in the monitor path
   restarts the shell.
5. **Workspaces follow monitors by rule**, not by script: workspaces 1-5 go
   to the primary, 6-10 + the named workspaces to the highest-priority other
   output when there is one (on hephaestus: the lg). The rules are re-issued by
   `refresh()` when the primary changes; Hyprland moves workspaces off a
   removed monitor by itself, and on re-add the policy re-homes the pinned
   ones (`hl.dispatch` move-workspace-to-monitor).
6. **`SUPER+ALT+N` = Nth monitor from the left**: a Lua bind that sorts
   `hl.get_monitors()` by `x` and moves the current workspace there.
   `move_workspace_to_monitor.sh` and `monitor-change.sh` go.
7. **Monique** stays usable for experimenting: it writes
   `~/.config/hypr/monitors.lua`, which is now the repo file, so its output shows
   up in `git diff`. Because the table above is data and Monique writes
   `hl.monitor{}` calls, point Monique at `monitors.local.lua` instead (if it
   allows a path), which `monitors.lua` applies last when present and which is
   git-ignored; copy settings you like into the table.

## Open questions

- Laptop + external with the lid **open**: panel off (today's behaviour) or
  extend? Default kept as "off".
- Priorities: is acer > tv > nreal > lg > laptop the order you want? With the
  TV and the acer never connected at the same time it mostly matters for
  hephaestus (acer over lg).
- Does `hl.get_monitors()` include disabled outputs? If not, the policy keeps
  its own "known connected" set from the added/removed events. Check on hermes.
- Lid switch: is there a `switch:` bind in the Lua API, or do we use
  `hl.on`/logind? Check the stubs/wiki before implementing.
- hephaestus layout: is the acer/lg arrangement (LG left, acer right) still right?
