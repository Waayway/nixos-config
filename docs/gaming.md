# Gaming on hephaestus

hephaestus is the gaming desktop (Ryzen with an AMD GPU, Hyprland). This page covers what
`programs.games.enable` sets up, how it compares with CachyOS, whether Hyprland is a
problem, and how to move to something lighter if it is. Nothing here has been measured on
the machine yet: it is from the configuration, the Hyprland docs and general knowledge,
and the measuring section says how to check it.

## What is configured

- `modules/workstation/games/games.nix` (`programs.games.enable`): Steam with GE-Proton as an
  extra compatibility tool, Gamescope (with the "Steam (Gamescope)" session), Heroic
  (Epic, GOG, Amazon), MangoHud, protontricks. Firewall holes for Steam Remote Play and
  LAN game transfers.
- `modules/workstation/games/scopebuddy.nix` and `scopebuddy_home.nix`: ScopeBuddy
  (`scb`), from Bazzite, packaged from the pinned 1.5.0 release, and its defaults file.
  See "Gamescope with ScopeBuddy".
- `modules/workstation/games/tuning.nix` (`programs.games.tuning.enable`, default on):
  the CachyOS-style tuning, below. `programs.games.tuning.scheduler = null` turns the
  scheduler off.
- `modules/workstation/desktop/hyprland/config/lua/games.lua`: direct scanout, VRR while
  fullscreen, tearing and idle-inhibit for Steam and Gamescope windows. Scanout is
  `render.direct_scanout = 2` (only windows with content type "game"), and the gamescope
  and `steam_app_*` rules give those windows `content = "game"` themselves (checked:
  a nested gamescope shows `contentType: game` in `hyprctl clients`). Scanout for every
  fullscreen window (1) gives black screens with native-Wayland Proton outside gamescope
  in some games (Hyprland discussion #14843). Plain files, no
  switch needed: `hyprctl reload`, then `hyprctl configerrors` (this applies to every
  machine that uses this Hyprland config, the laptop included).
- `modules/workstation/apps/streamdeck.nix` (`workstation.apps.streamdeck.enable`): Bitfocus
  Companion (buttons for MangoHud's mangoapp, Discord and music), a user service with its web UI on http://localhost:8000, plus the udev rule
  that lets the logged-in user talk to the Stream Deck (replug it after the first switch).
  It comes from nixpkgs-unstable; the stable nixpkgs does not have it.
- `modules/workstation/desktop/hyprland/autostart.nix` (`workstation.autostart`): commands
  started with the Hyprland session, per host. hephaestus starts `steam -silent` (Steam in
  the tray) and `high-tide` (TIDAL, below).
- `modules/workstation/storage/homelab.nix` (`workstation.storage.homelab.enable`):
  TrueNAS at `/store` and `/archive`, automounted on first access.

## Gamescope with ScopeBuddy

Gamescope is not started by hand. ScopeBuddy (`scb`) wraps a game's command, starts
gamescope around it with the defaults in `~/.config/scopebuddy/scb.conf` (written from
`scopebuddy_home.nix`), and fixes the Steam overlay and Steam Input inside nested
gamescope. The defaults: fullscreen, `--mangoapp` (MangoHud's overlay, which Companion
can drive), and ScopeBuddy's three auto variables, `SCB_AUTO_RES`, `SCB_AUTO_HDR` and
`SCB_AUTO_VRR`: it reads the monitor's current resolution, HDR and VRR state and adds
`-W/-H`, `--hdr-enabled` and `--adaptive-sync` to match.

**Steam launch option, per game:** `scb -- %command%`. Steam has no global launch option,
so this is typed once per game (Properties, General, Launch Options). It is the same line
for every game; per-game gamescope arguments go in
`~/.config/scopebuddy/AppID/<steam appid>.conf`, and `SCB_NOSCOPE=1 scb -- %command%` runs
a game without gamescope. Heroic: Settings, Advanced, Wrapper command `scb` with the
argument `--`; ScopeBuddy recognises Heroic's launch command (not tried here yet).

**Which monitor.** The nested gamescope is a window on Hyprland, so Hyprland decides where
it opens. The gaming workspace opens on the primary monitor (the highest `priority` in
`monitors.lua`, the Acer 4K 144 Hz on hephaestus; falls back to the next monitor when it
is off), and the rules in `rules.lua` send `gamescope` there. A Proton game started
without `scb` (class `steam_app_*`) goes to the same workspace. Only running games go
there: Steam itself, Heroic and the browser are on whatever workspace you put them on
(Super+1, Super+2, ...), and Super+G switches to the gaming one.

**Workspaces and monitors.** No workspace belongs to a monitor: every workspace can be
shown on every monitor, and one opens on the monitor you are on. The only default is the
gaming workspace, which opens on the primary monitor, and a gaming workspace you have
already moved stays where you put it. **Super+Shift+Tab** turns the workspaces the monitors show one step around, left to right
(Hyprland's `swap_monitors`, called in a row). With two monitors that is a plain swap, so
both keep working either way round; with three or more it is a rotation, so the one on the
last monitor wraps to the first and there is no pair to choose. **Super+Ctrl+Shift+Tab**
turns the other way. With a single monitor it does nothing. Other people solve three
monitors with one bind per pair (Hyprland discussion #3364), with linked switching that moves
all monitors together (gist `workspaces.sh`, the hyprspaces plugin), or by changing the
workspace model (split-monitor-workspaces); rotation is the one that is still a swap on two
monitors. `Super+Alt+<n>` still moves the current workspace to the nth monitor from the left.

**The one `-O`.** On Hyprland ScopeBuddy has no idea which monitor is the primary one, and
the auto variables abort the launch ("Primary display not supported", checked against the
real script) unless gamescope is given `-O <connector>`. So `scb.conf` passes it, taken
from `$XDG_RUNTIME_DIR/hypr/primary-monitor` (written by `monitor_policy.lua`), not
hardcoded, so it follows the large monitor. If that file is missing the auto variables
are switched off and gamescope starts plain instead of the game failing.

**To tweak at the machine.** Not set up yet, and not tested here:

- HDR (set up, not yet tried with a game): the desktop stays SDR (`cm` is the default
  `srgb`, `bitdepth = 10`), and Hyprland switches the monitor to HDR while a fullscreen
  window asks for it (`render.cm_auto_hdr`, default 1 on 0.55). A monitor with `hdr = true`
  in `monitors.lua` (the Acer: about 1060 nits; the LG's 350 nits is not worth it) makes
  `monitor_policy.lua` write `$XDG_RUNTIME_DIR/hypr/primary-monitor-hdr`, and `scb.conf`
  then adds `--hdr-enabled` and exports `DXVK_HDR=1`, so the game offers its HDR option.
  `SCB_HDR=0 scb -- %command%` turns it off for one game. No vk-hdr-layer or
  `ENABLE_HDR_WSI`: Mesa 25.1+ has it built in and the layer breaks gamescope. If a game
  only offers HDR while the screen is already in HDR, `quirks.prefer_hdr = 2` (gamescope
  only) is the next thing to try. Known on AMD: the screen can stay in HDR (very bright)
  after a fullscreen HDR app closes with `bitdepth = 10`; scRGB games (Control) show
  wrong colours, HDR10 ones work. Test with `scb -- vkcube` first.
- VRR: `SCB_AUTO_VRR` reads wlr-randr's adaptive_sync flag; with Hyprland's `vrr = 2`
  (only while fullscreen) that flag may be off when the game starts.
- Whatever else the CachyOS setup had (Proton Wayland, per-game `AppID/*.conf` files):
  put the stable ones in `scopebuddy_home.nix`.

`capSysNice` for gamescope is off: a capability wrapper inside Steam's sandbox is a known way to get a game that
does not start, and scx and ananicy cover the priorities.

## Looks outside Plasma

Plasma themes everything; on Hyprland each toolkit gets it from `desktop/theme_home.nix`:

- GTK4/libadwaita (High Tide) and Electron/Chromium (Heroic, Discord) follow the portal's
  `org.freedesktop.appearance color-scheme`, which xdg-desktop-portal-gtk reads from dconf.
  `gtk.colorScheme = "dark"` sets it; without it they are light.
- Qt (Qt5 and Qt6): qt6ct/qt5ct as the platform theme, the Breeze style, and a Tokyo Night
  palette generated from `tools/color.nix`.
- Steam draws its own dark interface (CEF). Wine/Proton dialogs have no dark mode; a dark
  `.reg` colour scheme per prefix (`protontricks <appid> regedit`) is the known fix, not done.

## CachyOS compared

What makes CachyOS feel quick, and what hephaestus gets:

- Scheduler: CachyOS ships BORE in its kernel. Here: sched_ext `scx_lavd` (latency-aware,
  made for desktops and games) on the mainline kernel (`boot.kernelPackages =
  linuxPackages_latest`, 7.2 now). `scx_bpfland` is the other one to try. Check with
  `systemctl status scx` or `cat /sys/kernel/sched_ext/root/ops`.
- ananicy-cpp with the CachyOS rule set: same package and rules CachyOS uses.
- zram swap (zstd) and the `vm.*` values that go with it.
- `vm.max_map_count = 2147483642` (Proton needs it; NixOS defaults to 1048576) and
  `kernel.split_lock_mitigate = 0`.
- gamemode (`gamemoderun %command%`).
- btrfs mounted with `noatime`.
- Not matched: CachyOS's kernel is built with x86-64-v3 optimisations and extra
  patches. See "Going further".

Expect the same feel in most games; the last few percent is the kernel and the x86-64-v3
builds. Where it does not match, measure before changing anything (below).

## Is Hyprland too heavy?

Probably not. From `hyprland/config/lua/`:

- Effects on: window blur (kawase, 1 pass), shadows (range 4), rounding 10, animations
  for windows, borders, fades and workspaces. Blur and shadows are on because Hyprland's
  defaults are, and only cost anything on screen while a desktop is being drawn.
- Desktop extras running all the time: Quickshell (the Qt bar and notifications),
  hypridle, hyprpaper, nm-applet. Light, but not nothing.
- Hyprland itself: its compositing cost is small. The cost that matters for a game is
  indirect: every frame is composited and queued, which adds latency and can add
  stutter. Hyprland did not scan a fullscreen game out directly (`render.direct_scanout`
  defaults to 0; now 2 with `content = "game"` rules), and `general.allow_tearing = true` did nothing without an `immediate`
  rule per game. `games.lua` fixes both, plus VRR while fullscreen.
- `vfr` (only redraw on change) is on; leave it.

So the likely wins are not in moving off Hyprland. If a fullscreen game runs well and
`hyprctl monitors` shows no `tearingBlockedBy` while it is up, the compositor is out of
the way.

Levers, in order, before changing window manager:

1. Gamescope through ScopeBuddy: Steam launch option `scb -- %command%` (above). The game
   renders into Gamescope, which presents it directly.
2. The Steam Gamescope session (`steam-gamescope`): no desktop compositor at all while
   playing. Pick it from the login screen or run it from a TTY.
3. Turn the effects off while playing, without editing files:
   `hyprctl eval 'hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false } }, animations = { enabled = false } })'`
   (it goes back to the config on the next `hyprctl reload`).

## Measuring

- In the game: `mangohud %command%` shows FPS, 1% lows, frametime and CPU/GPU load.
  Compare with CachyOS using the same game and settings; 1% lows matter more than average.
- `hyprctl monitors` while the game is fullscreen: look at `tearingBlockedBy` and whether
  VRR is active.
- Is the scheduler loaded: `systemctl status scx`. Is ananicy running: `systemctl status
  ananicy-cpp`. Is gamemode on for a game: `gamemoded -s` while it runs.
- LACT (installed) shows GPU clocks and power; check the card reaches its boost clocks.

## If a performance problem shows up: other window managers

Quickshell, hypridle, hyprlock and hyprpaper only need Wayland protocols that wlroots
compositors support (layer shell, idle notify, session lock), so they would move over. What is
Hyprland specific: the Lua config in `hyprland/config/` (binds, rules, monitor policy)
and `greetd.nix`'s session command.

- sway (wlroots): no blur, shadows or animations at all; direct scanout, VRR
  (`adaptive_sync`) and tearing (`allow_tearing`) are supported. The most conservative
  choice. Costs: rewriting binds and rules, no animations.
- Hyprland with everything off (above) gets most of the same.
- niri is the other lightweight option (scrolling tiling); same idea.

To switch: a new module next to `modules/workstation/desktop/hyprland/` with `programs.sway.enable`
and a config tree linked like the Hyprland one, and `greetd.nix`'s `session` pointing at it.
Hyprland can stay installed and selectable from tuigreet.

## Going further

- CachyOS kernel on NixOS: the `chaotic-cx/nyx` flake provides `linuxPackages_cachyos`
  (BORE, x86-64-v3 variants) with its own binary cache. It needs a new flake input and
  its cache key, and the project's status and cache availability must be checked before
  using it. Not applied: a kernel is hard to undo on a machine you boot into daily.
- A `linuxPackages_zen` kernel is a smaller step with a plain nixpkgs package.
- GPU: LACT is there for a power profile or an undervolt; `programs.gamemode` is not set
  to touch the GPU so the two do not fight.

## TIDAL

High Tide, started with the session onto the music workspace (`workstation.autostart`,
`rules.lua`; `silent`, so logging in does not jump to it). It is the `high-tide` app in
`workstation.apps.media`, so every host with `media` enabled gets it, the laptop too.

**Why not a web view.** The first pick here was SONE, described as "native". Only its
backend is Rust: the interface is a React page in a Tauri webview, so it is a browser and
lags like one. tidal-hifi is Electron, the same thing. The candidates below are the ones
packaged in nixpkgs that draw their own interface with a real toolkit (all need a TIDAL
subscription):

- **High Tide** (`pkgs.high-tide`, GTK4/libadwaita with Python, GPL-3.0, very active):
  the most mature of the open ones. Quality selectable, GStreamer playback with an optional
  ALSA output, MPRIS, background playback, Discord presence. Needs a keyring for the
  login, which hephaestus has (gnome-keyring).
- **Tonearm** (`pkgs.tonearm`, GTK4/libadwaita with Go, GPL-3.0, beta since January):
  a compiled binary, so likely the lightest on start-up and memory. Gapless, MPRIS,
  background playback, lyrics, plays at the highest quality it is offered (24-bit/48 kHz).
  Younger, fewer settings. Swap it in if High Tide is still too slow: `pkgs.tonearm` in
  `media.nix`, the command `tonearm`, the class `dev.dergs.Tonearm` in `rules.lua`.
- **SONE** (`pkgs.sone`, Tauri webview), **tidal-hifi** (Electron): the web-view ones,
  left out. (This repo had tidal-hifi with the TidaLuna mod before; commit f7478db
  replaced both with OxiTide.)
- **OxiTide** is installed through Flatpak on every `media` host as before: Rust and GTK4,
  freeware but not open source, so it was not considered a candidate.

Not tested on hardware: whether High Tide's window class is its application id
(`io.github.nokse22.high-tide`; the workspace rule depends on it, check with
`hyprctl clients`), and the keyring. The session starts through greetd's `initial_session`,
which logs in without a password, so gnome-keyring may still be locked when High Tide
starts and ask for its password once.

## Steam on Hyprland

**Windows.** Steam is an XWayland client (class `steam`) and Hyprland tiles every window by
default, so the Friends List, Settings, chat and update dialogs were tiled next to the main
window. `hyprland/config/lua/steam.lua` floats everything except the main window (title
`Steam` or `Steam Big Picture Mode`). Static rules only see the title a window has when it
opens, hence `initial_class` and `initial_title`; and the widely copied `negative:Steam`
would keep "Steam Settings" and "Sign in to Steam" tiled (their titles contain "Steam"), so the
main window is matched by its whole title. Also in there: the "Launching..." splash is
centred, notification toasts do not take focus, and XWayland ghost windows without class
or title do not take focus (the last one is from CachyOS's Hyprland defaults).
Where it came from: Hyprland's wiki for the rule syntax, the r/hyprland thread
"Floating Steam Properties", CachyOS's `cachyos-hypr-noctalia` rules and caelestia's.
Not run in Hyprland here: `hyprctl reload`, `hyprctl configerrors`, then `hyprctl clients`
shows the real titles if one still tiles (add it to the rule).

**Blurry or pixelated.** Steam only runs through XWayland, and Hyprland scales an XWayland
window by stretching its bitmap, so on a monitor with scale 2 (the Acer; 1.6 on the LG, 2.5 on
the TV) the client is soft. People fix it with two settings that only work together:
Hyprland's `xwayland.force_zero_scaling` (XWayland windows are drawn at the real pixels:
sharp but 1x, so tiny) and `STEAM_FORCE_DESKTOPUI_SCALING` (Steam draws its own interface
bigger). **Since the 64-bit Steam client (November 2026) the variable is ignored** (the
string is gone from the client), so `lua/xwayland.lua` also loads `Xft.dpi: 96 × scale` with
`xrdb` when the session starts; CEF on X11 takes its scale from it, and other X programs get
the same size. `programs.games.steamScale = 2;` on hephaestus does both: it sets the variable in
Steam's environment (checked in the built profile, next to extest's and Proton-GE's) and
creates `/etc/hypr/xwayland-zero-scaling`, which `lua/xwayland.lua` turns into the Hyprland
setting, so the laptop is not affected. **Needs a log out and in**, XWayland starts with the
session.

What it costs: there is one scale for all monitors, so Steam is the right size on the Acer
(2), 25% too big but sharp on the LG (1.6) and a bit small on the TV (2.5); change the number
to favour another. Every XWayland-only program is drawn at 1x and is tiny (Wayland-native
ones are not: Firefox, Discord, High Tide, the bar). Proton games started outside gamescope
now see the monitor's real resolution instead of the scaled one, which is what they want.
The cursor over Steam and other XWayland windows: `home.pointerCursor` (theme_home.nix)
puts the Rosé Pine XCursor theme in `~/.icons` (Steam's container sees the home folder and
the store), and `lua/xwayland.lua` sets `XCURSOR_SIZE` to 32 × the scale in the marker
file, so it is not 1x. Possible follow-up, not done: Steam may forget its library folders after
the first start with the variable (re-add `/mnt/games`; reported by steamtinkerlaunch's
notes). A native Wayland Steam does not exist: Valve's issue #7224 is open, and patching
`steamwebhelper` to Wayland, which people try, breaks the store and menus. Settings, Interface
in Steam also has its own scale slider.

## Steam Controller

The Steam Controller (2026): in desktop mode on Hyprland Steam cannot create its virtual
mouse, so the trackpad cursor is invisible or dead as soon as Steam runs, while games still
work (ValveSoftware/steam-for-linux#13185, open; Hyprland discussion #14426; the NixOS wiki
page on Steam). `programs.games.steamController.enable` (on for hephaestus,
`steam-controller.nix`) turns on `programs.steam.extest`, which translates Steam's X11 input
into uinput events, and adds `hidapi` to Steam's environment, which the wiki asks for with
this controller. The udev rules and the uinput module are already there through
`programs.steam`.

Caveats from that issue, not checked here: the trackpads stop while Steam's settings or
Steam Input menu is open (leave the window and they come back); one report says a
controller update made Steam crash when the controller turns on, with a hand-built extest
(nixpkgs has 1.0.2, upstream is at 1.0.4). If Steam misbehaves set
`programs.games.steamController.enable = false`. If the cursor moves but cannot be seen,
Hyprland's `cursor.no_hardware_cursors = true` is the other thing people tried (a report
says it stopped working on the Lua builds). `~/.steam/steam/logs/controller.txt` shows what
Steam thinks the controller is. If it is the original 2015 controller, tell me: it is a
different problem.

## MangoHud

`modules/workstation/games/mangohud/MangoHud.conf` (preset order, keybinds, log folder) and
`presets.conf` (the compact top bar, the full-detail layout, off), linked to
`~/.config/MangoHud/` by `mangohud_home.nix`. Both `mangohud %command%` and gamescope's
`--mangoapp` read them. They are live: edit them in `~/.flake`, Shift_L+F4 reloads. Keys:
Shift_R+F10 cycles the presets, Shift_R+F12 toggles the HUD, Shift_L+F2 logs to
`~/mangologs`. A file goverlay already wrote there is moved to `*.before-nix` on the first
switch.

## Extra drives

Two btrfs drives are mounted in `hosts/workstations/hephaestus.nix`, named as on the old
setup: `/mnt/bep` (1.8T NVMe) and `/mnt/games` (1.1T SATA). By UUID, `nofail` with a 5 second
device timeout so a missing drive never holds up the boot, and no compression (only the boot
drive has `compress=zstd:1`). After the first switch run `sudo chown waayway: /mnt/bep
/mnt/games` once, then add the folder as a Steam library (Steam, Settings, Storage). Keep
Proton game data off NTFS. The two Windows disks are not mounted; they share filesystem
UUIDs, so use `/dev/disk/by-id/` if one is ever needed.

## NFS

`/store` is `10.0.10.130:/mnt/store/internal`, `/archive` is
`10.0.10.130:/mnt/archive/shares`, root-squashed, so file ownership follows what TrueNAS
maps. Mounted on first access with a 15 second mount timeout, `nofail`, so the desktop and
boot never wait for the NAS. Off the LAN the NAS is only reachable through the tailnet's
subnet route.
