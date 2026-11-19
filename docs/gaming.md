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
  fullscreen, tearing and idle-inhibit for Steam and Gamescope windows. Plain files, no
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

- HDR: `--hdr-enabled` needs the Gamescope WSI layer for games to see HDR
  (`ENABLE_GAMESCOPE_WSI=1`, per gamescope's own help text), and the HDR state ScopeBuddy
  reads on Hyprland is a stub in 1.5.0, so `SCB_AUTO_HDR` may add nothing until you add
  `--hdr-enabled` yourself. Hyprland's own HDR (the `cm`/`bitdepth` monitor keys in
  `monitors.lua`) also has to be on for it to show.
- VRR: `SCB_AUTO_VRR` reads wlr-randr's adaptive_sync flag; with Hyprland's `vrr = 2`
  (only while fullscreen) that flag may be off when the game starts.
- Whatever else the CachyOS setup had (Proton Wayland, per-game `AppID/*.conf` files):
  put the stable ones in `scopebuddy_home.nix`.

`capSysNice` for gamescope is off: a capability wrapper inside Steam's sandbox is a known way to get a game that
does not start, and scx and ananicy cover the priorities.

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
  defaults to 0), and `general.allow_tearing = true` did nothing without an `immediate`
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
