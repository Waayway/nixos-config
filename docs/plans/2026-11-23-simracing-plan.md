# Sim racing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Moza R5 bundle, SR-P Lite clutch and HGP shifter usable on hephaestus, with the ES wheel's RPM LEDs driven by game telemetry and the Stream Deck working as a 16-button virtual button box.

**Architecture:** One new NixOS module in this repo (`modules/workstation/games/simracing.nix`) installs Boxflat + its udev rule, packages and runs moza-rev as a user service, and runs the button-box daemon as a user service. The daemon (Rust, uinput) and the `buttonbox` Companion module (TypeScript) live in `github:Waayway/companion-modules`, like the existing `mangohud` module; this repo only consumes its flake and holds the Companion layout.

**Tech Stack:** NixOS modules, `rustPlatform.buildRustPackage`, Rust + `evdev` crate (uinput), TypeScript + `@companion-module/base` ~2.1.3, yarn 4, Node 26.

**Spec:** `docs/plans/2026-11-23-simracing-design.md`

## Global Constraints

- Repo rules in `AGENTS.md` apply: module gated with `lib.optionalAttrs hostPlatform.isLinux { config = lib.mkIf (… && !hostPlatform.isServer) { … }; }`; host files thin; never `//` on shared top-level keys; nixfmt from the repo's nixpkgs.
- Commit only your own paths (`git commit -m "…" -- <paths>`); conventional messages; **no `Co-Authored-By` or other AI trailer** (both repos). Never stash/reset. No worktrees. **Ask Thijs before any push or `nixos-rebuild switch`.**
- moza-rev pinned to commit `6a3cf66c734dde29126e6d9b296adeab4479d005` (github `francisdb/moza-rev`).
- Boxflat from nixpkgs (`pkgs.boxflat`, 1.35.5); its `99-boxflat.rules` gives `uaccess` on Moza `ttyACM*` (vendor `346e`) and `/dev/uinput`. No `dialout` group.
- Button box: uinput device name **`Companion Button Box`**, **32 buttons**, fixed vendor/product IDs `0x1209`/`0x0001`, bus USB; socket `$XDG_RUNTIME_DIR/companion-buttonbox.sock`; line protocol `down <n>\n` / `up <n>\n`, n = 1–32.
- Joystick button numbers (contract, never renumber): ignition 1, starter 2 (hold), pit limiter 3, headlights 4, flash 5 (hold), wipers 6, horn 7 (hold), look back 8 (hold), TC + 9, TC − 10, ABS + 11, ABS − 12, brake bias + 13, brake bias − 14, DRS 15, radio 16 (hold). Tap = down, ~80 ms, up.
- Companion pages: **RACING** (page 4, buttons 1–12) and **RACING 2** (page 5, buttons 13–16, 8 empty keys). Stream Deck MK.2, 3 rows × 5 columns; column 0 of every page is `pageup` / `pagenum` / `pagedown`. GAMING unchanged; no back key.
- companion-modules work happens in a clone at `~/companion-modules` (`git clone https://github.com/Waayway/companion-modules ~/companion-modules`); test it from this repo with `--override-input companion-modules ~/companion-modules` until Thijs has pushed it.

## Review Focus

- Daemon started while a client holds a button and the client (Companion) dies or restarts → every button it held is released (no stuck horn / starter). Test: Task 3 `release_all_on_disconnect`.
- Malformed or out-of-range lines (`down 0`, `down 33`, `foo`, empty line, missing newline at EOF) → ignored with a warning, connection stays open. Test: Task 3 `parse_rejects_*`.
- Companion connection enabled before the daemon is running, or the daemon restarts → module shows disconnected, reconnects within ~2 s, no crash. Test: Task 4 `reconnects after server restart`.
- Two Companion keys holding the same button and one released → button stays down until both are up. Test: Task 3 `shared_hold_counts`.
- Wheel unplugged / plugged later → moza-rev service keeps running and does not flood the journal (upstream retries every 3 s, logs once). Checked in Task 1 step "service idles".

---

### Task 1: simracing module — Boxflat, moza-rev, docs (this repo)

**Files:**
- Create: `modules/workstation/games/simracing.nix`
- Modify: `hosts/workstations/hephaestus.nix` (options block, next to `programs.games.steamScale`)
- Modify: `docs/gaming.md` (new section "Sim racing", and a bullet in "What is configured")

**Interfaces:**
- Produces: option `programs.games.simracing.enable` (bool, default false); user service `moza-rev`; `boxflat` and `moza-rev` on PATH. Task 6 adds to this file.

- [ ] **Step 1: Write the module.** Shape and header comment like `scopebuddy.nix`. `let moza-rev = pkgs.rustPlatform.buildRustPackage { pname = "moza-rev"; version = "0.1.0-unstable-2026-04-30"; src = fetchFromGitHub { owner = "francisdb"; repo = "moza-rev"; rev = <pinned>; hash = lib.fakeHash; }; cargoHash = lib.fakeHash; nativeBuildInputs = [ pkg-config ]; buildInputs = [ udev ]; meta.mainProgram = "moza-rev"; }`. Config: `environment.systemPackages = [ pkgs.boxflat moza-rev ]`, `services.udev.packages = [ pkgs.boxflat ]`, `systemd.user.services.moza-rev = { description = "Moza wheel RPM LEDs from game telemetry (moza-rev)"; wantedBy = [ "default.target" ]; serviceConfig = { ExecStart = lib.getExe moza-rev; KillSignal = "SIGINT"; Restart = "on-failure"; RestartSec = 5; }; }`. Gate: `config.programs.games.simracing.enable && !hostPlatform.isServer`.
- [ ] **Step 2: Enable on hephaestus.** `programs.games.simracing.enable = true;` with a one-line comment pointing at `docs/gaming.md`.
- [ ] **Step 3: `git add` the new file, fill the hashes.** Run `nix build --no-link -L .#nixosConfigurations.hephaestus.config.system.build.toplevel` and copy each "got: sha256-…" into `hash`, then `cargoHash`. If the crate's tests need hardware, set `doCheck = false` with a comment saying why.
  Expected end state: toplevel builds.
- [ ] **Step 4: Evaluate all hosts + options.**
  Run the five `nix eval … drvPath` commands from `AGENTS.md` and `nix flake check --no-build --keep-going`: all succeed.
  `nix eval .#nixosConfigurations.hephaestus.config.programs.games.simracing.enable` → `true`;
  `nix eval .#nixosConfigurations.hermes.config.programs.games.simracing.enable` → `false`;
  `nix eval --json .#nixosConfigurations.hephaestus.config.services.udev.packages --apply 'map (p: p.pname or p.name)'` contains `"boxflat"`.
- [ ] **Step 5: Docs.** In `docs/gaming.md` add "Sim racing": hardware list; kernel driver (`hid-universal-pidff`, nothing to install); first plug-in in Boxflat (firmware, FFB, rotation, wheel RPM **Telemetry Mode = Telemetry**); moza-rev (`journalctl --user -u moza-rev`, `moza-rev configure` for per-game setup); per game: BeamNG OutGauge 127.0.0.1:4444, AC needs nothing in-game plus the Proton launcher workaround (non-Steam shortcut to `acs.exe`, `steam_appid.txt` = `244210`), AMS2 UDP "Project CARS 2" + the iptables loopback rule from moza-rev's README (not in config), Forza Data Out 127.0.0.1:9999; ACC has no RPM; close Boxflat if the LEDs misbehave; turn off Steam Input for a game that sees the wheel twice.
- [ ] **Step 6: Format and commit.** nixfmt (repo's) on the two .nix files.
  `git commit -m "feat(games): sim racing module with Boxflat and moza-rev RPM LEDs" -- modules/workstation/games/simracing.nix hosts/workstations/hephaestus.nix docs/gaming.md`
- [ ] **Step 7: Checkpoint — switch (ask Thijs first).** `sudo nixos-rebuild switch --flake ~/.flake#hephaestus`. Then: `udevadm cat 2>/dev/null | grep -c 346e` ≥ 1 (or `grep 346e /etc/udev/rules.d/*boxflat*`); `ls -l /dev/uinput` shows an ACL for waayway (`getfacl /dev/uinput`); **service idles:** `systemctl --user is-active moza-rev` → `active`, and `journalctl --user -u moza-rev -n 20` shows one "no Moza wheelbase found yet" line, not a stream.

### Task 2: companion-modules — Cargo crate skeleton and flake package

**Files (in `~/companion-modules`):**
- Create: `daemons/buttonbox/Cargo.toml`, `daemons/buttonbox/Cargo.lock`, `daemons/buttonbox/src/main.rs`
- Modify: `flake.nix` (package `buttonbox-daemon`; devShell adds `cargo rustc rustfmt clippy`)
- Modify: `README.md` (one paragraph: what the daemon is, that it must run for the `buttonbox` module)

**Interfaces:**
- Produces: flake output `packages.<system>.buttonbox-daemon` with `bin/companion-buttonbox` (`meta.mainProgram = "companion-buttonbox"`). Task 6 consumes it. The `default` package (Companion modules folder) stays modules-only.

- [ ] **Step 1:** Crate `companion-buttonbox`, edition 2024, deps: `evdev` (latest 0.13.x, uinput via `VirtualDevice`), `log`, `env_logger`. `main.rs` prints usage for `--help` only for now.
- [ ] **Step 2:** `flake.nix`: `buttonbox-daemon = pkgs.rustPlatform.buildRustPackage { pname = "companion-buttonbox"; version = from Cargo.toml; src = ./daemons/buttonbox; cargoLock.lockFile = ./daemons/buttonbox/Cargo.lock; }` added to `packages` next to the modules (not inside `default`).
- [ ] **Step 3:** `git add -A daemons flake.nix && nix build --no-link -L .#buttonbox-daemon` → builds; `result/bin/companion-buttonbox --help` exits 0.
- [ ] **Step 4:** `git commit -m "feat(buttonbox): daemon crate skeleton and flake package" -- daemons flake.nix README.md`

### Task 3: companion-modules — daemon: protocol, hold tracking, uinput, socket

**Files:**
- Create: `daemons/buttonbox/src/protocol.rs`, `daemons/buttonbox/src/state.rs`, `daemons/buttonbox/src/device.rs`
- Modify: `daemons/buttonbox/src/main.rs`

**Interfaces:**
- Consumes: Task 2 crate.
- Produces: the socket protocol in Global Constraints (consumed by Task 4). Internal:
  - `protocol::parse(line: &str) -> Result<Command, ParseError>`; `enum Command { Down(u8), Up(u8) }` (1-based, 1..=32).
  - `state::Holds` — `new() -> Self`; `down(&mut self, client: u64, n: u8) -> Option<(u8, bool)>`; `up(&mut self, client: u64, n: u8) -> Option<(u8, bool)>`; `release_client(&mut self, client: u64) -> Vec<(u8, bool)>`. Each returns the device transitions to emit (`(button, pressed)`), i.e. only when a button's total hold count goes 0→1 or 1→0.
  - `device::ButtonBox` — `create() -> io::Result<Self>`; `set(&mut self, n: u8, pressed: bool) -> io::Result<()>` (emits key event + SYN).

- [ ] **Step 1: Failing tests** (`#[cfg(test)]` in each file):
  - `parse_accepts`: `parse("down 1") == Ok(Down(1))`, `parse("up 32") == Ok(Up(32))`, `parse("down 7\r") == Ok(Down(7))`.
  - `parse_rejects_range`: `parse("down 0")`, `parse("down 33")` are `Err`.
  - `parse_rejects_garbage`: `parse("")`, `parse("foo 1")`, `parse("down x")`, `parse("down 1 2")` are `Err`.
  - `shared_hold_counts`: `down(a,5) == Some((5,true))`; `down(b,5) == None`; `up(a,5) == None`; `up(b,5) == Some((5,false))`.
  - `up_without_down_is_noop`: `up(a,3) == None`.
  - `repeat_down_same_client_is_idempotent`: `down(a,4)` twice then one `up(a,4) == Some((4,false))`.
  - `release_all_on_disconnect`: `down(a,1); down(a,2); down(b,2)`; `release_client(a) == vec![(1,false)]` (2 still held by b).
- [ ] **Step 2:** `cargo test` in `daemons/buttonbox` (devShell) → the tests fail to compile / fail.
- [ ] **Step 3: Implement `protocol` and `state`.** `Holds` keeps a per-client `HashSet<u8>` and a per-button count.
- [ ] **Step 4:** `cargo test` → all pass.
- [ ] **Step 5: Implement `device::ButtonBox::create`.** Button codes in this order (index i → button i+1, which is also the order SDL/Wine number them): `BTN_TRIGGER..=BTN_DEAD` (0x120–0x12f, 16), `BTN_SOUTH..=BTN_THUMBR` (0x130–0x13e, 15), `BTN_TRIGGER_HAPPY1` (0x2c0) = 32. Also `ABS_X` and `ABS_Y`, range −32767..32767, value 0, never moved (Wine's DirectInput and some games ignore axis-less devices). Name, IDs and bus from Global Constraints.
- [ ] **Step 6: Implement `main`.** Socket path = `$XDG_RUNTIME_DIR/companion-buttonbox.sock` (override `--socket <path>`); remove a stale socket file before bind; one thread per client (or a small poll loop) reading lines; each client gets a u64 id; parse errors → `warn!` and continue; on EOF/error → `release_client` and emit. Shared `Holds` + `ButtonBox` behind a `Mutex`. SIGTERM/SIGINT: release all and exit 0. `RUST_LOG` default `info`.
- [ ] **Step 7: Manual check on hephaestus** (needs Task 1 switched for `/dev/uinput` access): `cargo run` in one terminal; `evtest` lists "Companion Button Box" at `/dev/input/eventN`; `udevadm info /dev/input/eventN` shows `ID_INPUT_JOYSTICK=1`; `printf 'down 3\n' | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/companion-buttonbox.sock` → evtest shows `BTN_THUMB2` (button 3) pressed, then released when socat exits (release-on-disconnect).
- [ ] **Step 8:** `cargo fmt`, `cargo clippy -- -D warnings` clean; `nix build .#buttonbox-daemon` (Cargo.lock updated).
- [ ] **Step 9:** `git commit -m "feat(buttonbox): uinput button box daemon with socket protocol" -- daemons`

### Task 4: companion-modules — `buttonbox` Companion module

**Files:**
- Create: `modules/buttonbox/` mirroring `modules/mangohud/` (package.json, yarn.lock, `.yarn-missing-hashes.json`, tsconfig*.json, eslint.config.mjs, LICENSE, `companion/manifest.json`, `companion/HELP.md`), `src/main.ts`, `src/config.ts`, `src/client.ts`, `src/client.test.ts`, `src/actions.ts`, `src/presets.ts`, `src/upgrades.ts`
- Modify: `flake.nix` `moduleSpecs` (add `buttonbox.hash`)

**Interfaces:**
- Consumes: the socket protocol (Task 3).
- Produces: module id **`buttonbox`**; config field `socketPath: string` (default: empty = `$XDG_RUNTIME_DIR/companion-buttonbox.sock`); actions `press` `{ button: number }`, `release` `{ button: number }`, `tap` `{ button: number }` (1–32). Task 5 writes these ids into the Companion config. `class ButtonBoxClient { constructor(path: string, onStatus: (connected: boolean) => void); start(): void; send(cmd: 'down' | 'up', n: number): void; destroy(): void }`.

- [ ] **Step 1: Failing tests** in `src/client.test.ts` (node:test, a `net.createServer` on a temp-dir socket):
  - `sends down and up lines`: `send('down', 9); send('up', 9)` → server receives `"down 9\nup 9\n"`.
  - `reports disconnected when no server, then connects`: start client first, status false; start server; status true within 3 s.
  - `reconnects after server restart`: close server (status → false), start again on same path → status true within 3 s and a later `send('down',1)` arrives.
  - `drops sends while disconnected`: `send` while down does not throw and is not replayed after reconnect (a stale "down" must never arrive late).
  - `destroy closes the socket`: server sees `end`.
- [ ] **Step 2:** `yarn test` in `modules/buttonbox` → fails.
- [ ] **Step 3: Implement `ButtonBoxClient`** with `node:net`, retry every 2 s; then `main.ts` (`InstanceStatus.Ok` / `Disconnected` from `onStatus`), actions (`tap` = down, `setTimeout` 80 ms, up), presets: one per button 1–32 in two categories ("Hold" with press/release, "Tap"). Manifest like mangohud's, `id`/`name` `buttonbox`, description "Virtual joystick button box for sim racing (needs companion-buttonbox running)", permissions as narrow as Companion allows for a Unix socket in `$XDG_RUNTIME_DIR`.
- [ ] **Step 4:** `yarn test` → pass; `yarn lint` clean.
- [ ] **Step 5:** Add `buttonbox.hash = lib.fakeHash` to `moduleSpecs`, `nix build -L .#buttonbox` → copy the real hash; `nix build .#default` contains `share/companion-modules/buttonbox/`.
- [ ] **Step 6: Live check:** with the daemon from Task 3 running and Companion started with `--extra-module-path` pointing at `result/share/companion-modules` (or from this repo with `--override-input`), add a buttonbox connection → status OK; a test button with `press`/`release` shows in `evtest`.
- [ ] **Step 7:** `git commit -m "feat(buttonbox): Companion module that presses the virtual button box" -- modules/buttonbox flake.nix`

### Task 5: companion-modules — config tool that adds the RACING pages

**Files:**
- Create: `tools/companion-config/add-racing.mjs`, `tools/companion-config/add-racing.test.mjs`
- Modify: `tools/companion-config/README.md` (usage)

**Interfaces:**
- Consumes: module id and action ids from Task 4.
- Produces: `node tools/companion-config/add-racing.mjs <in.companionconfig> <out.companionconfig>`; exported `addRacing(config: object): object` for the test. Task 6 runs it on `~/.flake/modules/workstation/apps/companion/wdesktop.companionconfig`.

Format facts (from the current export, `version` 12, gzip'd JSON — read/write like `convert.mjs`): connections are in `instances` keyed by a 21-char id (`{ moduleInstanceType: "connection", moduleId, moduleVersionId: "dev", updatePolicy: "stable", sortOrder, label, isFirstInit: false, secrets: {}, lastUpgradeIndex: -1, enabled: true, config: {} }`); pages in `pages["<n>"] = { id, name, gridSize, controls, pageVariables }`; `controls[row][col]`; nav cells `{type:"pageup"}`, `{type:"pagenum"}`, `{type:"pagedown"}`; buttons `type: "button-layered"`, style layers `box0` (background colour) and `text0` (label), actions in `steps["0"].action_sets.down/up` as `{ type: "action", id, definitionId, connectionId, options: { button: { isExpression: false, value: n } }, upgradeIndex: -1 }`.

- [ ] **Step 1: Failing tests** (node:test on a minimal fixture config with one GAMING page and its nav column):
  - `adds a buttonbox connection`: exactly one instance with `moduleId === "buttonbox"`, label `buttonbox`.
  - `adds RACING and RACING 2 as pages 4 and 5` with GAMING's `gridSize` and the nav column (`pageup`/`pagenum`/`pagedown` in col 0).
  - `button mapping`: RACING `controls[0][1]` label `IGN` with down `[tap 1]`; `[0][2]` `START` with down `[press 2]` and up `[release 2]`; ... every entry of the Global Constraints table at: RACING row 0 = 1–4, row 1 = 5–8, row 2 = 9–12; RACING 2 row 0 = 13–16, rows 1–2 empty. Labels: IGN, START, PIT, LIGHTS, FLASH, WIPER, HORN, LOOK BACK, TC +, TC −, ABS +, ABS −, BB +, BB −, DRS, RADIO.
  - `idempotent`: `addRacing(addRacing(c))` deep-equals one run apart from fresh ids (same connection reused, pages replaced, still 5 pages).
  - `leaves pages 1–3, other instances and surfaces untouched`.
- [ ] **Step 2:** `node --test tools/companion-config/` → new tests fail.
- [ ] **Step 3: Implement** — button style cloned from an existing GAMING button (deep copy), then `text0.text` and `box0.color` set; hold buttons a distinct background colour from tap buttons; feedbacks emptied.
- [ ] **Step 4:** `node --test tools/companion-config/` → pass.
- [ ] **Step 5:** `git commit -m "feat(companion-config): add-racing tool for the RACING pages" -- tools/companion-config`
- [ ] **Step 6: Checkpoint — ask Thijs to push companion-modules** (`git push origin HEAD:main`, or his preferred branch). Nothing in this repo may reference unpushed commits in `flake.lock`.

### Task 6: wire the button box into this repo

**Files:**
- Modify: `modules/workstation/games/simracing.nix`
- Modify: `flake.lock` (`nix flake update companion-modules`)
- Modify: `modules/workstation/apps/companion/wdesktop.companionconfig`
- Modify: `docs/gaming.md`

**Interfaces:**
- Consumes: `inputs.companion-modules.packages.${system}.buttonbox-daemon` (Task 2), module folder (already loaded by `streamdeck.nix`), `add-racing.mjs` (Task 5).

- [ ] **Step 1: Service.** In `simracing.nix` (add `inputs` to the module args), a second `lib.mkIf` inside a `lib.mkMerge`: when `programs.games.simracing.enable && config.workstation.apps.streamdeck.enable`, `systemd.user.services.companion-buttonbox = { description = "Virtual joystick for the Stream Deck RACING pages"; wantedBy = [ "default.target" ]; serviceConfig = { ExecStart = lib.getExe <buttonbox-daemon>; Restart = "on-failure"; RestartSec = 2; }; }`. Check the real option path for the streamdeck enable with `nix eval .#nixosConfigurations.hephaestus.config.workstation.apps.streamdeck.enable` → `true`.
- [ ] **Step 2:** After Thijs pushed: `nix flake update companion-modules`. All five host evals + `nix flake check --no-build --keep-going` pass; `nix eval .#nixosConfigurations.hephaestus.config.systemd.user.services.companion-buttonbox.enable` → `true`; same on hermes → error/absent (service not defined).
- [ ] **Step 3: Layout.** Ask Thijs whether the running Companion has edits not in the repo's export; if so he exports first and the export replaces `wdesktop.companionconfig`. Then `node ~/companion-modules/tools/companion-config/add-racing.mjs modules/workstation/apps/companion/wdesktop.companionconfig modules/workstation/apps/companion/wdesktop.companionconfig`. Update the comment in `streamdeck.nix` that lists pages/connections (RACING, RACING 2; buttonbox).
- [ ] **Step 4: Docs.** `docs/gaming.md` "Sim racing" gets a "Stream Deck button box" part: the RACING / RACING 2 table with button numbers (Global Constraints), "bind once per game in its controls menu; the device is *Companion Button Box*", `systemctl --user status companion-buttonbox`, `companion-import` replaces the whole Companion config.
- [ ] **Step 5:** nixfmt, then `git commit -m "feat(games): Stream Deck RACING pages as a virtual button box" -- modules/workstation/games/simracing.nix modules/workstation/apps/streamdeck.nix modules/workstation/apps/companion/wdesktop.companionconfig flake.lock docs/gaming.md`
- [ ] **Step 6: Checkpoint (ask Thijs): switch and import.** `sudo nixos-rebuild switch --flake ~/.flake#hephaestus`; `systemctl --user is-active companion-buttonbox` → `active`; `companion-import`; on the deck, page down to RACING: pressing IGN shows a button press in `evtest` on "Companion Button Box", holding HORN holds it until release; in a Proton game's control settings the device is listed and binding PIT registers button 3. Ask Thijs before pushing `unstable`.
