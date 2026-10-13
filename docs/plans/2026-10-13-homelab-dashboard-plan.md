# Homelab dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every hosted application appears in Lodestar's Services tab, declared in this flake.

**Architecture:** Service modules declare `lodestar.links.<id>` inside their own `mkIf`;
`modules/homelab/links.nix` lists the services not on NixOS yet; `modules/lodestar/server.nix`
feeds `inputs.lodestar.lib.linksFrom` into `services.lodestar-server.links`.

**Tech Stack:** Nix (NixOS, nix-darwin), the `lodestar` flake input.

**Spec:** `docs/plans/2026-10-13-homelab-dashboard-design.md`; the feature itself:
`~/lodestar/docs/plans/2026-10-13-service-links-design.md`.

## Global Constraints

- **Prerequisite:** the lodestar plan (`~/lodestar/docs/plans/2026-10-13-service-links-plan.md`)
  is done and pushed to lodestar's main branch. Without it `lodestar.links` doesn't exist.
- Follow `AGENTS.md`: every module imported everywhere and switching itself off; no `//`
  on shared top-level keys; nixfmt from the repo's nixpkgs; new files `git add`ed; commit
  only your paths; conventional commits ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; author
  `Thijs van Waaij <thijs@vanwaaij.com>`; ask before pushing.
- Link ids are unique across the flake. Groups used: `Apps`, `Media`, `Games`, `Backups`,
  `Infrastructure`.

## Review Focus

- A workstation (atlas, apollo, hermes, hephaestus) must evaluate with no links and no
  change in behaviour (Task 2 evaluates all five hosts and checks `lodestar.links == {}` on
  them).
- A public name that hairpins from nixos-manager: its card must not show down while the
  service is up (Task 3 probes each URL from nixos-manager before choosing `check.url`).
- A self-signed UI (TrueNAS on its IP): up, not `TLS error` (Task 3, `insecureTls`).
- The Lodestar link itself must not be probed (it would only ever report itself)
  (`check.enable = false`, asserted in Task 2).
- `links.nix` declaring links on a host that isn't the server would double them up: the
  `mkIf` on `services.lodestar-server.enable` (asserted in Task 2: only nixos-manager has the
  manual ids).

---

### Task 1: Update the lodestar input and wire `linksFrom`

**Files:**
- Modify: `flake.lock`, `modules/lodestar/server.nix`

- [ ] **Step 1:** `nix flake update lodestar`; confirm
  `nix eval .#nixosConfigurations.hermes.options.lodestar.links.type.description` prints an
  attribute-set type (the option exists).
- [ ] **Step 2:** In `modules/lodestar/server.nix`, next to `hosts`, add
  `links = inputs.lodestar.lib.linksFrom { inherit (inputs.self) nixosConfigurations darwinConfigurations; };`
- [ ] **Step 3: Verify** the five host evaluations from `AGENTS.md` succeed and
  `nix eval .#nixosConfigurations.nixos-manager.config.services.lodestar-server.links --json`
  prints `{}`.
- [ ] **Step 4: Commit** `feat(lodestar): service links from every configuration` (`flake.lock`, `modules/lodestar/server.nix`).

### Task 2: Declare the links

**Files:**
- Create: `modules/homelab/links.nix`
- Modify: `modules/backup/backrest.nix`, `modules/lodestar/server.nix`

- [ ] **Step 1: Failing check** — run
  `nix eval .#nixosConfigurations.nixos-manager.config.services.lodestar-server.links --json | jq -S 'keys'`
  Expected now: `[]`. Target after this task:
  `["archipelago","backrest","jellyfin","lodestar","nextcloud","proxmox","traefik","truenas"]`.
- [ ] **Step 2:** `backrest.nix`: inside its `mkIf`, `lodestar.links.backrest = { title =
  "Backrest"; group = "Backups"; description = "Browse and restore restic snapshots"; url =
  "http://${cfg.listenAddress}:${toString cfg.port}"; };`
- [ ] **Step 3:** `server.nix`: `lodestar.links.lodestar = { title = "Lodestar"; group =
  "Infrastructure"; description = "Fleet manager"; url = "http://${cfg.listenAddress}:${toString cfg.listenPort}"; check.enable = false; };`
  (with `cfg = config.services.lodestar-server`, inside the existing `mkIf`).
- [ ] **Step 4:** `modules/homelab/links.nix` with the entries from the spec (Nextcloud,
  Jellyfin, Archipelago, Traefik, Proxmox, TrueNAS), wrapped in
  `config = lib.mkIf (config.services.lodestar-server.enable or false) { … };`. Leave
  `check.url` / `insecureTls` as in the spec for now; Task 3 settles them. Format with nixfmt;
  `git add`.
- [ ] **Step 5: Verify**
  - the `jq 'keys'` command above prints the target list;
  - every link has `host` set: `… | jq -e 'all(.[]; .host != "")'`;
  - `lodestar.check.enable == false`;
  - each workstation: `nix eval .#darwinConfigurations.atlas.config.lodestar.links --json`
    → `{}` (same for apollo, and `nixosConfigurations.hermes/hephaestus`);
  - all five `drvPath` evaluations and `nix flake check --no-build --keep-going` pass.
- [ ] **Step 6: Commit** `feat(homelab): service links for the dashboard`

### Task 3: Settle check URLs against the live services

**Files:**
- Modify: `modules/homelab/links.nix`

- [ ] **Step 1:** From nixos-manager, for each manual link, run
  `ssh -J pve manager@10.0.10.170 'curl -s -o /dev/null -w "%{http_code} %{time_total}\n" --max-time 5 <url>'`
  (add `-k` to tell a TLS failure from a bad status). Record the result per link.
- [ ] **Step 2:** Per link: status in the default expect list → keep. Hairpin/timeout on the
  public name → set `check.url` to the LAN address that answers (and `insecureTls = true`
  if that needs `-k`). Self-signed → `insecureTls = true`. Anything still failing is a real
  outage: note it in the commit message, don't paper over it.
- [ ] **Step 3: Verify** evaluation (Task 2 Step 5 commands).
- [ ] **Step 4: Commit** `fix(homelab): check URLs that work from nixos-manager`

### Task 4: Roll out and document

**Files:**
- Modify: `docs/homelab.md`

- [ ] **Step 1:** `docs/homelab.md`: a "Dashboard" section — the Services tab in Lodestar;
  links live next to their service module (`lodestar.links.<id>`), non-NixOS ones in
  `modules/homelab/links.nix` and move out when a VM migrates; `check.url` /
  `insecureTls` for hairpin and self-signed cases. Commit `docs(homelab): dashboard`.
- [ ] **Step 2:** Ask the user before pushing `unstable`; then promote to `stable` and apply
  nixos-manager through Lodestar (`docs/lodestar.md`).
- [ ] **Step 3: Verify on the machine**: `ssh -J pve manager@10.0.10.170 'jq length /etc/lodestar-server/links.json'`
  → `8`; open the dashboard, `#/services`: every link `Up` (or down for a reason that
  matches reality), Lodestar `Not checked`, the Backrest card on nixos-manager with a green
  host dot.
