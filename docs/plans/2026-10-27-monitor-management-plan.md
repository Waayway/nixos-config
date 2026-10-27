# Monitor management: plan

Design: `2026-10-27-monitor-management-design.md`. Runs inside phase 1 of
`2026-10-27-hyprland-lua-quickshell-plan.md` (Lua files) and needs phase 3
(Quickshell bar per screen) before the eww restart path can go.

1. **Check the API** on hermes (`hyprctl eval` / the stubs in
   `${pkgs.hyprland}/share/hypr/stubs/hl.meta.lua`): `monitor.added` /
   `monitor.removed` callback arguments, whether `get_monitors()` lists
   disabled outputs, how to bind the lid switch, and the dispatcher for
   moving a workspace to a monitor.
2. **`monitors.lua`**: the data table (four known screens + laptop panel +
   Monique's TV colour settings) and a function `apply(name)` that calls
   `hl.monitor{}` for one entry; a catch-all rule for unknown screens.
3. **`monitor_policy.lua`**:
   - `refresh()`: look at connected outputs and lid state, enable/disable the
     panel per the rule, never leave zero outputs.
   - `pick_primary()`: highest `priority` among enabled outputs, unknown = 20,
     ties by `x` then size.
   - `publish(name)`: write `$XDG_RUNTIME_DIR/hypr/primary-monitor` atomically
     (`.tmp` + `os.rename`), only when it changed; emit `primary>>name` with
     `hl.dsp.event`.
   - Called on `hyprland.start`, `monitor.added`, `monitor.removed`, lid
     open/close.
   - Re-home pinned workspaces after an add or a primary change.
4. **Workspace rules** in `rules.lua`, issued from `refresh()`: 1-5 on the
   primary, 6-10 + named on the best other output.
4b. **Quickshell side** (with phase 3 of the Quickshell plan): `Primary.qml`
   singleton with a `FileView { path: "…/hypr/primary-monitor"; watchChanges: true }`
   exposing `screen` (match on `Quickshell.screens[i].name`, fallback
   `screens[0]`); `Bar` and the notification popups bind `screen` to it.
5. **`SUPER+ALT+1..0`** in `binds.lua`: sort outputs by `x`, move current
   workspace to the Nth.
6. **Delete** `scripts/monitor-change.sh`, `scripts/move_workspace_to_monitor.sh`,
   and `hyprland-monitor-attached` from `hyprland.nix`; move Monique output to
   `monitors.local.lua` (git-ignored) if Monique can target a path.
7. **Test matrix** (hermes unless noted), `hyprctl monitors all` after each:
   - boot with only the panel; `cat $XDG_RUNTIME_DIR/hypr/primary-monitor` = `eDP-1`;
   - plug external with lid open → panel off, primary file = external, bar
     moves to it, workspaces moved;
   - `pkill quickshell; quickshell &` → bar comes back on the primary;
   - close lid with external → no change; open lid → no change;
   - unplug external → panel back on, bar on panel, no crash;
   - unplug with lid closed → panel stays on (safety rule), lock on lid;
   - hephaestus: acer + lg positions, bar on the acer, workspaces 6-10 on lg, `SUPER+ALT+1/2`
     go left/right; TV downstairs gets its colour settings;
   - Nreal glasses plugged/unplugged.
