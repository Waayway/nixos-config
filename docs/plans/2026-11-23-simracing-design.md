# Sim racing on hephaestus

Status: approved 2026-11-23 (helper language changed to Rust at review).

Calls made by Claude, not Thijs (check these): Rust (over Go) for the button-box daemon;
the socket path and line protocol; tap length ~80 ms; AMS2 iptables rule as a doc note,
not config; the button-box service lives in `simracing.nix` and needs both
`programs.games.simracing.enable` and `workstation.apps.streamdeck.enable`.

## Why

Thijs wants to drive sims (Assetto Corsa, BeamNG and similar) on hephaestus with his Moza
gear: the **R5 Pro bundle** (R5 base + ES wheel + SR-P Lite pedals), the **SR-P Lite
clutch** add-on and the **HGP shifter**. The gear is not plugged in yet; the config should
be ready so that plugging it in is all that is left. Besides steering and force feedback,
the **RPM LEDs on the ES wheel** should follow the game, and the **Stream Deck** should
act as a button box with standard car controls (part 2).

## Goals

- Wheel, force feedback, pedals, clutch and shifter work in Steam/Proton games.
- Wheel settings (FFB strength, rotation, pedal curves, LED colours, firmware) can be
  changed on Linux.
- The ES wheel's RPM bar follows the engine in BeamNG and Assetto Corsa (and the other
  games moza-rev covers: DiRT Rally 2, AMS2, Forza), with nothing started by hand.

## Non-goals

- ACC RPM LEDs: ACC's UDP API has no RPM, moza-rev cannot drive the bar there (Thijs
  chose moza-rev knowing this).
- SimHub/Wine, dashboards, LED effects beyond the RPM bar, Monocoque.
- Other hosts (hermes, the Macs).

## Anti-goals

- Anything that needs a manual step after every switch or update (that is why SimHub
  under Wine was dropped).
- A service that spams errors or burns CPU while the wheel is unplugged.

## What already works (checked on hephaestus, 2026-11-23)

- Kernel 7.2.11 (`linuxPackages_latest`) has `CONFIG_HID_UNIVERSAL_PIDFF=m`, and the module
  has aliases for vendor `346E` (Moza). It loads on plug-in; no out-of-tree driver needed.
- The pedals and clutch connect to the base; the HGP connects to the base or by USB. Both
  show up as standard HID joysticks; nothing to configure.

## Approaches considered (for the RPM LEDs)

Boxflat does not read game telemetry: it only sets the wheel's LED mode (Off / Telemetry /
Static) and colours. A separate program has to send the RPM.

1. **moza-rev** (github.com/francisdb/moza-rev, Rust, MIT): listens for each game's UDP
   telemetry and writes the RPM bar over the base's serial port. Confirmed by its author
   on the R5 bundle with the ES wheel. **Chosen** (Thijs, 2026-11-23).
2. SimHub under Wine with the AZOM Moza plugin: most features and games, but serial
   passthrough into Wine and setup outside the config; fragile across updates.
3. Monocoque: lists the R5 for input, but has no Moza RPM LED output.

## Design

New module `modules/workstation/games/simracing.nix`, option
`programs.games.simracing.enable` (Linux only, `!isServer`, the usual
`lib.optionalAttrs hostPlatform.isLinux` + `lib.mkIf` shape). It sets:

- **Boxflat** (nixpkgs `boxflat`) in `environment.systemPackages`, and
  `services.udev.packages = [ pkgs.boxflat ]` for its `99-boxflat.rules`: `uaccess` + mode
  0666 on Moza `ttyACM*` devices (vendor `346e`) and `uaccess` on `/dev/uinput`. This
  rule also gives moza-rev its access, so no `dialout` group.
- **moza-rev**, packaged in the module with `rustPlatform.buildRustPackage` from the
  pinned commit `6a3cf66c734dde29126e6d9b296adeab4479d005` (2026-04-30, no release tags),
  using the repo's `Cargo.lock`. Dependency `serialport` needs `pkg-config` + `udev`
  (`systemd`) at build time. Also in `systemPackages`, for `moza-rev configure`.
- A **systemd user service** `moza-rev` (`systemd.user.services`, `wantedBy =
  [ "default.target" ]`, `Restart=on-failure`, `KillSignal=SIGINT`), replacing upstream's
  system unit that runs as a named user. moza-rev already waits for the wheel and
  reconnects after unplug/renumbering (retries on an interval), so it can run all the
  time. Default ports: AC 9996, BeamNG 4444, DR2 20777, AMS2 5606, Forza 9999, WRF2 23123;
  all loopback, no firewall change.

hephaestus host file: `programs.games.simracing.enable = true;`.

`docs/gaming.md`: a "Sim racing" section:

- First plug-in: open Boxflat, check firmware, set FFB/rotation, set the wheel's RPM
  **Telemetry Mode** to "Telemetry".
- Boxflat and moza-rev share the serial port; both open it non-exclusively, but if the
  LEDs misbehave, close Boxflat while driving.
- Per game: BeamNG OutGauge (127.0.0.1:4444; or `moza-rev configure`); AC works as is, and
  the Proton launcher workaround (non-Steam shortcut to `acs.exe` + `steam_appid.txt` with
  `244210`, which `moza-rev configure` can write); AMS2 UDP "Project CARS 2" plus the
  iptables loopback note from moza-rev's README; Forza Data Out 127.0.0.1:9999.
- If a game sees the wheel twice, turn off Steam Input for it.
- `journalctl --user -u moza-rev` for the service.

## Part 2: the Stream Deck as a button box

### Why and goal

Thijs wants "standard" car controls on the Stream Deck (Bitfocus Companion,
`modules/workstation/apps/streamdeck.nix`). Real sim-racing button boxes are game
controllers, so the deck becomes one: a **virtual joystick** whose buttons Companion
presses. Each game binds "joystick button N" once; nothing clashes with the keyboard, and
it works in gamescope and Proton whatever has focus.

### Approaches considered

1. **Virtual joystick (uinput) helper + a Companion module.** **Chosen** (Thijs,
   2026-11-23).
2. Fake keypresses with `ydotool` from Companion's "run shell command": no new code, but
   per-game key clashes, F13–F24 often ignored, shell latency.
3. Both (keys for menu shortcuts later): an add-on to 1, not now.

### Non-goals (part 2)

- Live state on the buttons (pit limiter lit, gear, flags): needs telemetry, whose UDP
  ports moza-rev already holds. Possible later, separate design.
- Per-game Companion pages or key bindings; binding happens in each game.

### Design

Two repos, like Lodestar: code in `github:Waayway/companion-modules`, values here.

**In companion-modules:**

- **`buttonbox-daemon`**: a small user daemon in **Rust** (Thijs: Rust or Go, not Python;
  Rust chosen because Lodestar and moza-rev are Rust; the `evdev` crate's uinput
  `VirtualDevice`, `rustPlatform.buildRustPackage`, `cargo fmt`) that creates one
  uinput device **"Companion Button Box"** with **32 buttons**, and listens on a Unix socket
  `$XDG_RUNTIME_DIR/companion-buttonbox.sock` for a line protocol: `down <n>`, `up <n>`
  (1–32). On socket disconnect it releases every held button (no stuck pit limiter).
  - The device must be classified as a joystick by udev (`ID_INPUT_JOYSTICK=1`) and seen by
    Proton/SDL and Wine's DirectInput: use buttons from the `BTN_JOYSTICK`/`BTN_GAMEPAD`
    ranges (`BTN_TRIGGER`..`BTN_DEAD`, `BTN_SOUTH`..`BTN_THUMBR`, then
    `BTN_TRIGGER_HAPPY*` if needed for 32) and, if Wine or SDL need it, a centred dummy
    `ABS_X`/`ABS_Y`. Checked with `evtest` and Steam's / a Proton game's controller list.
  - Vendor/product IDs fixed, so games remember bindings across restarts.
- **`buttonbox` Companion module** (TypeScript, same layout and Nix build as `mangohud`):
  connects to the socket (reconnects when the daemon restarts; connection status shows
  "disconnected" otherwise). Actions: **hold** button N (down on key press, up on key
  release, for horn/look back/push-to-talk) and **tap** button N (down, ~80 ms, up). A
  preset per button. No child processes, matching the repo's rule.
- The flake exports the daemon as a package next to the module folder.

**In this repo:**

- `simracing.nix`: when `programs.games.simracing.enable` and
  `workstation.apps.streamdeck.enable` are both on, a user service
  `companion-buttonbox` (`wantedBy default.target`, `Restart=on-failure`) runs the daemon.
  `/dev/uinput` access comes from Boxflat's `uaccess` rule, which the same module installs.
- `flake.lock`: `nix flake update companion-modules` after the module lands.
- `modules/workstation/apps/companion/wdesktop.companionconfig`: a **buttonbox**
  connection and two pages, **RACING** and **RACING 2**, after GAMING (pages 4 and 5). The
  deck is a Stream Deck MK.2 (3×5 = 15 keys) and every page keeps column 0 for page up /
  page number / page down, so 12 keys per page. No "back" key and no change to GAMING:
  the existing page up/down keys reach both (Thijs, 2026-11-23). Joystick button numbers in
  brackets, a contract once bound in games; also listed in docs/gaming.md:
  - RACING: ignition (1), starter (2, hold), pit limiter (3), headlights (4), flash
    (5, hold), wipers (6), horn (7, hold), look back (8, hold), TC + / − (9, 10),
    ABS + / − (11, 12).
  - RACING 2: brake bias + / − (13, 14), DRS (15), radio / push-to-talk (16, hold); the
    other 8 keys empty. Buttons 17–32 free.
  Applied with `companion-import` as today (it replaces the whole config; Thijs's UI edits
  since the last export must be exported first).
- `docs/gaming.md`: the RACING page, the button numbers, how to bind them per game, and
  `systemctl --user status companion-buttonbox`.

## Left to the builder

- Exact `buildRustPackage` hashes (`hash`, `cargoHash`), and whether the tests run in the
  sandbox (disable `doCheck` only if they need hardware).
- Whether the AMS2 iptables rule should go in the module (`networking.firewall.extraCommands`)
  or stay a doc note; default: doc note, Thijs did not name AMS2.

## Verification

- All five hosts evaluate; `nix flake check --no-build`.
- On hephaestus: the moza-rev package builds; `nixos-rebuild build` succeeds; after switch,
  `udevadm cat` (or `/etc/udev/rules.d`) contains the Boxflat rule and `systemctl --user
  status moza-rev` is running and logging "no Moza wheelbase found yet".
- Button box: daemon and module tests in companion-modules; after switch,
  `companion-buttonbox` runs, `evtest` lists "Companion Button Box" as a joystick, and
  pressing a RACING key shows the button in `evtest` and in a Proton game's control
  bindings.
- With the hardware (later, by Thijs): FFB in a game, Boxflat sees base/pedals/shifter,
  RPM bar moves in BeamNG and AC.
