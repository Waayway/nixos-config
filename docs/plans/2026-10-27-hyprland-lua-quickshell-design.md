# Hyprland Lua config + Quickshell: design

Status: implemented 2026-10-27 (hermes). Implementation steps: `2026-10-27-hyprland-lua-quickshell-plan.md`.
Monitor handling is its own design: `2026-10-27-monitor-management-design.md`.

## Why

Hyprland 0.55 configures in Lua. Today the Lua is generated from Nix
(`wayland.windowManager.hyprland.settings` with `mkLuaInline`, `_args`, `_var`
and `modBind` helpers, see `git show HEAD:modules/workstation/desktop/hyprland/hyprland_home.nix`).
That is Lua written through two layers of escaping: hard to read, every tweak
needs a `home-manager switch`, and the result can't be reloaded live.

Eww is the second problem: four bash daemons (`get-workspaces`, `media-status`,
`audio`, `battery`) poll or pipe `socat`/`playerctl`/`pactl` into JSON, the bar
is pinned to `:monitor 0`, and a monitor change does `eww kill && eww open bar`,
which is where it crashed.

## Decisions

1. **Plain Lua files in the repo, live-linked.** The Hyprland config is real
   `.lua` files in `modules/workstation/desktop/hyprland/config/`. Home-manager
   links `~/.config/hypr` to that folder with
   `config.lib.file.mkOutOfStoreSymlink "${home}/.flake/…/config"` (a link into
   the checkout, not the store), so an edit + `hyprctl reload` applies without a
   switch, and `git diff` shows what changed. Same pattern eww used, but through
   home-manager instead of a hand-written activation script.
2. **All Hyprland-ecosystem configs live in that folder**: `hyprland.lua` plus
   `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf` (these three are still
   hyprlang) and `scripts/`. One folder = everything in `~/.config/hypr`.
3. **Home-manager stops owning Hyprland's config.** `wayland.windowManager.hyprland`,
   `services.hypridle`, `programs.hyprlock` and `services.swaync` go away (they
   write into `~/.config/hypr` and would collide with the link). The system
   module (`programs.hyprland.enable`, portals, session) stays in
   `hyprland.nix`. hypridle and the bar start from Hyprland's
   `hl.on("hyprland.start")`.
4. **Split `hyprland.lua` by topic** with `require`:
   ```
   config/
     hyprland.lua        -- entry: sets package.path, requires the rest in order
     lua/
       vars.lua          -- mod, terminal, launcher, …
       theme.lua         -- loads generated colors (see 6)
       env.lua
       monitors.lua      -- monitor table (monitor-management design)
       monitor_policy.lua
       input.lua
       look.lua          -- general, decoration, animations, curves
       rules.lua         -- window/workspace rules, named workspaces
       binds.lua         -- every keybind, workspace loops in Lua
       autostart.lua
     hypridle.conf  hyprlock.conf  hyprpaper.conf
     scripts/            -- wallpaper-random.sh (move_workspace/monitor-change go, see monitor design)
     .luarc.json         -- points lua-ls at Hyprland's stubs (nixvim LSP)
   ```
   The `scripts/` folder moves here from `hyprland/scripts`, `scripts_home.nix` goes.
5. **Quickshell replaces Eww and swaync.** New `modules/workstation/desktop/quickshell/`
   with `quickshell_home.nix` and `config/` (QML), linked to
   `~/.config/quickshell` the same way. It uses Quickshell's own services
   instead of bash: `Quickshell.Hyprland` (workspaces, events),
   `Quickshell.Services.Mpris` (media), `Quickshell.Services.Pipewire`
   (volume), `Quickshell.Services.UPower` (battery), `SystemTray`, and
   `Quickshell.Services.Notifications` (replaces swaync). The bar is a
   `Variants { model: Quickshell.screens }`, one per monitor, created and
   **one** `PanelWindow` whose `screen` is the primary monitor. Hyprland has no
   primary, so the Hyprland Lua policy picks one and publishes it; when it
   changes, the bar moves (see `2026-10-27-monitor-management-design.md`,
   "Primary monitor"). No restart on hotplug.
   Notifications are Quickshell too (`NotificationServer`), shown as popups on
   the primary and in a toggleable panel (`SUPER+SHIFT+N` via `qs ipc call`).
   First version is feature parity with the eww bar (launcher, numbered +
   named workspaces, media with hover volume, clock, battery, tray) plus
   notifications; a control center is later.
6. **Everything is Tokyo Night (Night variant).** `tools/color.nix` becomes the
   official Tokyo Night Night palette (`bg #1a1b26`, `bg_dark #16161e`,
   `fg #c0caf5`, `blue #7aa2f7`, `magenta #bb9af7`, `cyan #7dcfff`,
   `green #9ece6a`, `yellow #e0af68`, `red #f7768e`, `comment #565f89`, …),
   matching what ghostty (`tokyonight_night`) and rofi (`tokyonight.rasi`)
   already use. From it:
   - Hyprland borders (`blue → magenta` gradient active, `comment` inactive);
   - hyprlock (replaces the Catppuccin variables; `catpuccin_lib.nix` and
     `catpuccin.conf` are deleted);
   - Quickshell bar and notifications;
   - GTK: `tokyonight-gtk-theme` (nixpkgs) dark variant instead of
     Colloid-Catppuccin in `theme_home.nix`; Papirus-Dark icons stay.
   Home-manager writes `~/.config/theme/colors.lua`, `colors.conf` (hyprlang,
   `source`d by hyprlock) and `Colors.qml` outside the linked folders, so
   nothing is generated into the git checkout (eww's
   `home.file.".flake/…/_colors.scss"` wrote into the repo and is why
   `_colors.scss` shows as modified).

## What stays the same

Keybinds, named workspaces (󰝚 󰭹 󰊴) and their window rules, animations,
gaps/borders, idle timings, hyprlock layout, rofi launcher, wallpaper rotation.
This is a port, not a redesign.

## Decided (2026-10-27)

- Config path is `~/.config/hypr`.
- Notifications move to Quickshell; swaync is dropped.
- Everything is Tokyo Night Night.
- One bar, on the primary monitor.

## Open questions

- Waybar and wlogout are still in `hyprland.nix`'s packages; drop waybar, keep
  wlogout until Quickshell has a power menu? (Plan assumes yes.)
