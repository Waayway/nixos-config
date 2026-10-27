# Hyprland Lua config + Quickshell: plan

Design: `2026-10-27-hyprland-lua-quickshell-design.md`. Hosts: hermes,
hephaestus (both Linux workstations, home-manager on). Commit per phase, own
paths only (the tree has unrelated staged work).

## Phase 0: preparation

1. Move the hand-made `~/.config/hypr` (default `hyprland.lua`, Monique's
   `monitors.lua/.conf`, empty `workspaces.conf`, old `hyprland.conf`) to
   `~/.config/hypr.bak-2026-10-27`; home-manager won't replace a real directory
   with a link. Same for `~/.config/eww` (already a link, just remove it).
2. Reference for the port: `git show HEAD:modules/workstation/desktop/hyprland/hyprland_home.nix`,
   `…/hypridle_home.nix`, `…/hyprlock_home.nix`, `…/swaynotificationcenter_home.nix`
   and the eww config under `HEAD:modules/workstation/desktop/eww/`.

## Phase 1: Hyprland as Lua files

1. Create `modules/workstation/desktop/hyprland/config/` with the layout from the
   design. Port from the old Nix one section at a time:
   - `vars.lua`: `mod = "SUPER"`, terminal `ghostty`, browser, file manager, rofi command.
   - `env.lua`: `HYPRCURSOR_THEME`, `HYPRCURSOR_SIZE`.
   - `input.lua`, `look.lua`: the `hl.config{ input, general, decoration, dwindle, misc }`
     block, the two curves and eight animations.
   - `rules.lua`: spotify/discord/gamescope → named workspaces.
   - `binds.lua`: all binds; the 1..0 loop as a Lua `for`; mouse binds with
     `{ mouse = true }`, volume/brightness with `{ repeating = true }`;
     `SUPER+SHIFT+N` toggles the Quickshell notification panel (phase 3) instead
     of `swaync-client`.
   - `autostart.lua`: `hl.on("hyprland.start")` → hypridle, hyprpaper,
     wallpaper script, nm-applet, `quickshell` (replaces `eww open bar`),
     hyprlock. `hyprland-monitor-attached` is dropped (monitor plan).
   - `monitors.lua` + `monitor_policy.lua`: from the monitor plan; until then a
     straight port of the four `hl.monitor{}` entries.
2. `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf` as hyprlang files ported
   from the old home-manager settings (same timeouts, layout, fingerprint).
3. Move `hyprland/scripts/` to `hyprland/config/scripts/`; delete `scripts_home.nix`.
4. `.luarc.json` with the stubs path. The store path changes per Hyprland
   version, so generate it from Nix (`${pkgs.hyprland}/share/hypr/stubs`) into
   `~/.config/theme/` or reference it via `$HYPRLAND_STUBS`; don't hard-code a
   store path in the repo.
5. `hyprland_home.nix` becomes:
   ```nix
   { config, lib, hostPlatform, ... }:
   lib.optionalAttrs hostPlatform.isLinux {
     xdg.configFile."hypr".source =
       config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.flake/modules/workstation/desktop/hyprland/config";
   }
   ```
   (`wayland.windowManager.hyprland` stays off, so it no longer writes `hyprland.lua`.)
6. `hyprland.nix`: add `hypridle`, `hyprlock`, `jq`; drop `waybar`,
   `hyprland-monitor-attached` (after the monitor plan lands).
7. Theme:
   - `tools/color.nix` → Tokyo Night Night palette (keep the existing key
     names so callers don't break, add the Tokyo Night names alongside).
   - `theme_home.nix` writes `~/.config/theme/colors.lua`, `colors.conf`
     (hyprlang) and `Colors.qml` from it, and swaps GTK to
     `tokyonight-gtk-theme` (dark).
   - `hyprlock.conf` `source`s `colors.conf`; delete `catpuccin_lib.nix`,
     `catpuccin.conf`.
8. Verify: `nix eval` hermes + hephaestus toplevel, `nix flake check --no-build`;
   on hermes `hyprctl reload` and `hyprctl configerrors` empty; spot-check binds,
   rules, animations, lock, idle.

## Phase 2: remove Eww

1. Delete `modules/workstation/desktop/eww/` (already deleted in the working
   tree, `style/_colors.scss` is staged-modified: unstage/delete together).
2. Drop `eww`, `socat` from packages. Done in the same commit as phase 3 so
   there's never a session without a bar.

## Phase 3: Quickshell

1. `modules/workstation/desktop/quickshell/quickshell_home.nix`: `home.packages = [ quickshell ]`
   (nixpkgs 0.3.0), link `~/.config/quickshell` → `…/quickshell/config` with
   `mkOutOfStoreSymlink`, generate `~/.config/theme/Colors.qml`.
2. `config/` QML:
   ```
   shell.qml              -- ShellRoot: one Bar, one NotificationPopups, NotificationPanel
   Primary.qml            -- singleton: screen named in $XDG_RUNTIME_DIR/hypr/primary-monitor (monitor plan)
   Theme.qml              -- imports ~/.config/theme/Colors.qml
   Bar.qml                -- PanelWindow on Primary.screen, top, 70% width, 58px, 20px margins, exclusive zone
   modules/Launcher.qml   -- runs rofi
   modules/Workspaces.qml -- Hyprland.workspaces; numbered 1-10 always, named ones from rules
   modules/Media.qml      -- Mpris.players[0], prev/play/next, title/artist, hover → volume
   modules/Volume.qml     -- Pipewire.defaultAudioSink, scroll ±5%, click mute, pavucontrol
   modules/Clock.qml
   modules/Battery.qml    -- UPower.displayDevice, hidden when no battery; tooltip with time left
   modules/Tray.qml       -- SystemTray
   notifications/         -- NotificationServer, popups on Primary.screen (top right,
                             timeouts 10s / 5s low / sticky critical, like swaync),
                             history panel; IpcHandler "notifications" { toggle, clear, dnd }
   ```
   Layout ported from the eww bar (pill workspaces, music gradient), colours
   from Tokyo Night.
3. Named workspaces: read their names from Hyprland (`Hyprland.workspaces`
   with non-numeric names) plus a static list in QML matching `rules.lua`; no
   config-file grepping.
4. Verify on hermes (battery, one screen) and hephaestus (two screens): one
   bar, on the primary, workspaces follow focus, media/volume/tray work, notifications
   show (`notify-send test`), hotplug a screen without the bar disappearing.

## Phase 4: clean up

- Update `AGENTS.md` (layout: desktop/hyprland/config, desktop/quickshell) and
  note "edit + `hyprctl reload`, no switch needed".
- Run nixfmt on touched `.nix` files.

## Risks

- `mkOutOfStoreSymlink` requires the checkout at `~/.flake` (true on every host).
- A Lua error leaves Hyprland on its fallback config; `hyprctl configerrors`
  after every reload, and keep the `.bak` folder until both hosts are verified.
- Quickshell 0.3 QML API: check the module names against the installed version
  (`quickshell --version`, docs at quickshell.org) before writing the QML.
