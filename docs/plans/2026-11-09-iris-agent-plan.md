# iris (Hermes Agent VM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A NixOS VM `iris` (VM 101) that runs Hermes Agent as a Discord bot on Thijs's
ChatGPT plan, with free OpenRouter fallback, Claude Code for coding, read-only Grafana,
and its dashboard at `https://agent.vanwaaij.com` on the tailnet only.

**Architecture:** Upstream's NixOS module (`inputs.hermes-agent.nixosModules.default`,
native systemd mode) is imported on every NixOS host and switched on by a new feature
module `modules/server/agent/` when `homelab.agent.enable` is set (only in
`hosts/servers/iris.nix`). Secrets come from opnix; the dashboard goes through the
router's existing route/gate machinery; state is copied nightly to a TrueNAS NFS share
that the existing restic run backs up.

**Tech Stack:** Nix flakes, NixOS modules, hermes-agent's NixOS module, opnix,
Traefik routes via `homelab.routes`, Kanidm gate via `homelab.access`, Tailscale
Services, TrueNAS module (`modules/server/truenas/homelab.nix`), restic.

**Spec:** `docs/plans/2026-11-09-iris-agent-design.md`

## Global Constraints

- Host `iris`, VM 101, `10.0.10.101/24`, `tag:iris`, `fleet = true`, servers folder
  (follows `stable`).
- Every module is always imported; the agent module turns itself off with
  `lib.optionalAttrs hostPlatform.isLinux { config = lib.mkIf cfg.enable { … }; }`
  (AGENTS.md "How a module turns itself off"). Folder `modules/server/` ⇒ gate on a
  server-only option.
- Never merge with `//` where both sides can share a top-level key; use `lib.mkMerge`.
- Discord: `DISCORD_ALLOWED_USERS = "137629736993030144"`,
  `DISCORD_HOME_CHANNEL = "1569317421251039294"`, `DISCORD_REQUIRE_MENTION = "false"`,
  `DISCORD_IGNORE_NO_MENTION = "false"`. Never `DISCORD_ALLOW_ALL_USERS` /
  `GATEWAY_ALLOW_ALL_USERS`.
- 1Password Homelab items: `iris-discord`/`token`, `iris-openrouter`/`credential`,
  `iris-grafana`/`token`, `iris-dashboard`/`password` (and `iris-dashboard`/`secret`
  for the session HMAC key, added in Task 2).
- Dashboard: `agent.vanwaaij.com`, `public = false`, `auth.gate = true`, members
  `[ "thijs" ]`, backend `http://10.0.10.101:9119`, router `10.0.10.110` the only
  trusted proxy. Not `hermes.*` (MagicDNS clash with the laptop).
- No pay-per-token providers: no `ANTHROPIC_API_KEY`, no `OPENAI_API_KEY`.
- The `hermes` user: no sudo, not in `wheel`, no SSH keys to other hosts.
- Formatting: repo nixfmt
  (`$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixfmt)/bin/nixfmt <files>`).
- Commits: conventional, own paths only (`git commit -m "…" -- <paths>`), as
  `thijs@vanwaaij.com`, no AI trailer. Ask before pushing.
- New files must be `git add`ed before evaluating.

## Review Focus

1. **Someone else messages the bot** (DM or in a channel): it must stay silent. Pinned by
   the Task 2 assertion that the allowlist is set and no allow-all variable exists.
2. **Dashboard reached without the gate** (from the LAN directly at `10.0.10.101:9119`,
   or with a forged `X-Forwarded-For`): only the router may connect. Pinned by the Task 3
   assertion that 9119 is opened for `10.0.10.110` only, not on the whole LAN interface.
3. **Secrets in the Nix store**: env file and token paths must be runtime paths under
   opnix's secret dir, never Nix path literals. Pinned by the Task 2 assertion that every
   `environmentFiles` entry starts with the opnix secrets prefix.
4. **Backup copies a half-written state** (SQLite sessions while the gateway writes):
   copy with `sqlite3 .backup` / `hermes backup`, not a raw `cp`. Pinned by the Task 4
   assertion on the backup script contents.
5. **First boot before the logins exist** (no `auth.json`): the gateway must keep
   running and answer on OpenRouter rather than crash-loop. Checked in Task 6 step
   "first start".

---

### Task 1: Host iris, flake input, agent module skeleton

**Files:**
- Modify: `flake.nix` (inputs)
- Modify: `lib/mkSystem.nix:115-117` (module list)
- Create: `hosts/servers/iris.nix`
- Create: `modules/server/agent/hermes.nix`
- Create: `tests/agent.nix`
- Modify: `programs.nix` (register `checks.x86_64-linux.agent`)

**Interfaces:**
- Produces: option `homelab.agent.enable` (bool, default false);
  `nixosConfigurations.iris`; check `checks.x86_64-linux.agent` that later tasks extend
  with more `assert`s. Constants in `hermes.nix` `let`: `host = "agent.vanwaaij.com"`,
  `port = 9119`, `stateDir = "/var/lib/hermes"`.

- [ ] **Step 1: Write the failing test** `tests/agent.nix`, same shape as
  `tests/cache.nix` (`{ pkgs, lib, nixosConfigurations }:`), with
  `iris = nixosConfigurations.iris.config` and these asserts:

```nix
assert iris.networking.hostName == "iris";
assert iris.homelab.agent.enable;
assert iris.services.hermes-agent.enable;
assert !iris.services.hermes-agent.container.enable;
assert iris.services.hermes-agent.stateDir == "/var/lib/hermes";
assert iris.services.hermes-agent.user == "hermes";
assert !(lib.elem "wheel" (iris.users.users.hermes.extraGroups or [ ]));
assert lib.all (n: !nixosConfigurations.${n}.config.services.hermes-agent.enable)
  (lib.attrNames (lib.removeAttrs nixosConfigurations [ "iris" ]));
pkgs.runCommand "agent-check" { } "touch $out"
```

  Register it in `programs.nix` like `checks.x86_64-linux.cache`.

- [ ] **Step 2: Run it to verify it fails**

Run: `git add tests/agent.nix && nix build --no-link .#checks.x86_64-linux.agent`
Expected: FAIL, `attribute 'iris' missing`.

- [ ] **Step 3: Add the input** in `flake.nix`:
  `hermes-agent = { url = "github:NousResearch/hermes-agent"; inputs.nixpkgs.follows = "nixpkgs"; };`.
  Run `nix flake lock --update-input hermes-agent`. If its package fails to build
  against our nixpkgs in Task 2's build step, drop the `follows` (note why in a comment).

- [ ] **Step 4: Import upstream's module** in `lib/mkSystem.nix` next to opnix and
  lodestar: `inputs.hermes-agent.nixosModules.default` (mkSystem is NixOS-only, so
  darwin is unaffected).

- [ ] **Step 5: Host file** `hosts/servers/iris.nix`, copied from `cache.nix`:
  `user = { name = "iris"; fullname = "Iris"; }`, IP `10.0.10.101`,
  `tags = [ "tag:iris" ]`, `fleet = true`, `options.homelab.agent.enable = true;`,
  a comment pointing at `modules/server/agent/` and `docs/agent.md`.

- [ ] **Step 6: Module skeleton** `modules/server/agent/hermes.nix`: header comment
  (what, where state lives, the manual logins, link to the design), declares
  `options.homelab.agent.enable = lib.mkEnableOption "Hermes Agent (Discord bot)"`,
  and under `mkIf` sets `services.hermes-agent = { enable = true; container.enable = false; user = "hermes"; group = "hermes"; stateDir = "/var/lib/hermes"; }`.

- [ ] **Step 7: Run the test and the usual evals**

Run: `git add -A hosts/servers/iris.nix modules/server/agent flake.nix flake.lock && nix build --no-link .#checks.x86_64-linux.agent`
Expected: PASS. Then the five `nix eval … drvPath` commands from AGENTS.md plus
`nix eval .#nixosConfigurations.iris.config.system.build.toplevel.drvPath`: all print a
path.

- [ ] **Step 8: Format and commit**

```bash
git commit -m "feat(agent): iris host and Hermes Agent module skeleton" -- flake.nix flake.lock lib/mkSystem.nix hosts/servers/iris.nix modules/server/agent/hermes.nix tests/agent.nix programs.nix
```

### Task 2: Hermes configuration, secrets, tools, Grafana MCP

**Files:**
- Modify: `modules/server/agent/hermes.nix`
- Create: `modules/server/agent/secrets.nix`
- Modify: `tests/agent.nix`

**Interfaces:**
- Consumes: `homelab.agent.enable`, the constants from Task 1.
- Produces: opnix secrets `irisDiscord`, `irisOpenrouter`, `irisGrafana`,
  `irisDashboardPassword`, `irisDashboardSecret`, and a rendered env file
  `config.services.onepassword-secrets.secretPaths.irisEnv` (or a oneshot that renders
  it, see Step 3) consumed by `services.hermes-agent.environmentFiles`.

- [ ] **Step 1: Extend the test** with asserts on `h = iris.services.hermes-agent`:

```nix
assert h.settings.model.provider == "openai-codex";
assert lib.hasSuffix ":free" (lib.head h.settings.fallback_providers).model;
assert (lib.head h.settings.fallback_providers).provider == "openrouter";
assert h.settings.auxiliary.compression.provider == "openrouter";
assert h.environment.DISCORD_ALLOWED_USERS == "137629736993030144";
assert h.environment.DISCORD_HOME_CHANNEL == "1569317421251039294";
assert h.environment.DISCORD_REQUIRE_MENTION == "false";
assert h.environment.DISCORD_IGNORE_NO_MENTION == "false";
assert !(h.environment ? DISCORD_ALLOW_ALL_USERS) && !(h.environment ? GATEWAY_ALLOW_ALL_USERS);
assert !(h.environment ? ANTHROPIC_API_KEY) && !(h.environment ? OPENAI_API_KEY);
assert h.environmentFiles != [ ] && lib.all (p: !(lib.hasPrefix "/nix/store" p)) h.environmentFiles;
assert lib.all (n: lib.any (p: lib.getName p == n) h.extraPackages)
  [ "claude-code" "codex" "git" "gh" "jq" "ripgrep" ];
assert h.mcpServers ? grafana;
assert h.backend.mode == "dashboard" && h.backend.host == "10.0.10.101" && h.backend.port == 9119;
assert h.settings.dashboard.public_url == "https://agent.vanwaaij.com";
assert h.settings.dashboard.trusted_proxies == [ "10.0.10.110" ];
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nix build --no-link .#checks.x86_64-linux.agent`
Expected: FAIL on the first new assert.

- [ ] **Step 3: `secrets.nix`** (same gate): five
  `services.onepassword-secrets.secrets.<name>` entries (references from Global
  Constraints, `iris-dashboard`/`secret` for `irisDashboardSecret`), owner `hermes`,
  mode `0400`, `services = [ "hermes-agent" "hermes-backend" ]`. opnix writes one value
  per file, so add a oneshot `hermes-env` (before both units, `RuntimeDirectory` 0700
  owned by hermes) that writes `/run/hermes-env/env` with
  `DISCORD_BOT_TOKEN`, `OPENROUTER_API_KEY`, `HERMES_DASHBOARD_BASIC_AUTH_USERNAME=thijs`,
  `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`, `HERMES_DASHBOARD_BASIC_AUTH_SECRET` from
  the secret files. `environmentFiles = [ "/run/hermes-env/env" ]`. (If opnix supports
  a templated multi-field file in this repo, use that instead, the way `whento-config`
  uses one `env` field: then ask Thijs to create `iris-config`/`env`.)

- [ ] **Step 4: `settings` and `environment`** in `hermes.nix`:
  - `settings.model = { provider = "openai-codex"; default = <model>; }`: `<model>` is
    the first model `hermes model` lists for "ChatGPT or Codex Subscription" in the
    pinned Hermes version (read it from `hermes_cli/provider_catalog.py` or the Codex
    provider profile in the locked source); comment that Thijs switches at runtime.
  - `settings.fallback_providers = [ { provider = "openrouter"; model = <free>; } ]`
    and `settings.auxiliary.{compression,vision}.{provider = "openrouter"; model = <free>;}`:
    `<free>` is a `:free` model that lists `tools` in `supported_parameters` at
    `https://openrouter.ai/api/v1/models` on the day of implementation.
  - `settings.dashboard = { public_url = "https://${host}"; trusted_proxies = [ "10.0.10.110" ]; }`.
  - `environment` = the four Discord values from Global Constraints plus
    `DISABLE_AUTOUPDATER = "1"` (Claude Code).
  - `backend = { mode = "dashboard"; host = lan.address; inherit port; waitFor = "interface"; interfaceName = lan.interface; }`
    with `lan = config.homelab.lan` and an assertion `lan.address != null` (as in
    whento.nix). If `waitFor = "interface"` makes it bind to an address other than
    `lan.address`, use `waitFor = null` (networkd sets the static IP early).
- [ ] **Step 5: Tools and MCP**:
  `extraPackages = with pkgs; [ claude-code codex git gh jq ripgrep ];` (nix is already
  on PATH system-wide). `mcpServers.grafana.command` = a `pkgs.writeShellScript` that
  exports `GRAFANA_URL=https://grafana.vanwaaij.com` and
  `GRAFANA_SERVICE_ACCOUNT_TOKEN="$(cat ${secretPaths.irisGrafana})"` then
  `exec ${pkgs.mcp-grafana}/bin/mcp-grafana` (keeps the token out of config.yaml).

- [ ] **Step 6: Run the test**

Run: `nix build --no-link .#checks.x86_64-linux.agent`
Expected: PASS.

- [ ] **Step 7: Build iris on nixos-manager** (bundle flow in AGENTS.md, branch
  `unstable`): `nix build --no-link -L .#nixosConfigurations.iris.config.system.build.toplevel`.
Expected: builds. If hermes-agent fails against our nixpkgs, apply Task 1 Step 3's fallback.

- [ ] **Step 8: Format and commit**

```bash
git commit -m "feat(agent): Hermes on Discord with ChatGPT, OpenRouter, Claude Code and Grafana" -- modules/server/agent tests/agent.nix flake.nix flake.lock
```

### Task 3: Dashboard route, gate, firewall, Lodestar link

**Files:**
- Create: `modules/server/agent/route.nix`
- Modify: `tests/agent.nix`

**Interfaces:**
- Consumes: `host`, `port`, `config.homelab.lan`.
- Produces: `homelab.routes.agent`, `homelab.access.agent`, `lodestar.links.agent`.

- [ ] **Step 1: Extend the test** (`router = nixosConfigurations.router.config`,
  `http = router.services.traefik.dynamicConfigOptions.http`, as in tests/cache.nix):

```nix
assert http.services.agent.loadBalancer.servers == [ { url = "http://10.0.10.101:9119"; } ];
assert http.routers.agent-tailnet.rule == "Host(`agent.vanwaaij.com`)";
assert !(http.routers ? agent-public);
assert lib.any (lib.hasSuffix "-gate") http.routers.agent-tailnet.middlewares;
assert router.services.tailscale.serve.services ? agent;
assert nixosConfigurations.identity.config.homelab.identity.provisionState.groups ? "agent-users";
assert !(lib.elem 9119 (iris.networking.firewall.interfaces.${iris.homelab.lan.interface}.allowedTCPPorts or [ ]));
assert lib.hasInfix "10.0.10.110" iris.networking.firewall.extraInputRules
  && lib.hasInfix "9119" iris.networking.firewall.extraInputRules;
```

  (Adjust the `provisionState` path to whatever `tests/identity.nix` uses for gated
  apps' groups; the point is `agent-users` exists with `thijs`.)

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL, `agent` missing.

- [ ] **Step 3: `route.nix`**: `homelab.routes.agent = { inherit host; backend = "http://${lan.address}:${toString port}"; public = false; auth.gate = true; };`,
  `homelab.access.agent = { members = [ "thijs" ]; gate = true; };`,
  `lodestar.links.agent = { title = "Hermes"; group = "Apps"; description = "AI agent (Discord bot)"; url = "https://${host}"; };`,
  and the firewall: port 9119 accepted from `10.0.10.110` only
  (`networking.firewall.extraInputRules` with nftables, or `extraCommands` with
  iptables: match whichever firewall backend the servers use).
  Monitoring (spec section 5): check `modules/server/monitoring/alerts.nix` for a
  generic failed-unit alert; if it doesn't cover every unit on every fleet host, add
  `hermes-agent.service` to it (and an assert in the test).

- [ ] **Step 4: Run the test**, then `nix flake check --no-build --keep-going`.
Expected: PASS; flake check has no new failures.

- [ ] **Step 5: Format and commit**

```bash
git commit -m "feat(agent): agent.vanwaaij.com on the tailnet behind the gate" -- modules/server/agent/route.nix tests/agent.nix
```

### Task 4: Backups of /var/lib/hermes

**Files:**
- Modify: `modules/server/truenas/homelab.nix` (NFS share + dataset)
- Create: `modules/server/agent/backup.nix`
- Modify: `modules/server/backup/homelab.nix` (repo `store` paths)
- Modify: `tests/agent.nix`

**Interfaces:**
- Produces: TrueNAS dataset `store/internal/iris` exported to `10.0.10.101` only;
  mount `/var/lib/hermes-backup` on iris; `hermes-backup.service` + `.timer` (daily
  01:30, before the 02:00 snapshot).

- [ ] **Step 1: Extend the test**:

```nix
assert iris.fileSystems."/var/lib/hermes-backup".device == "10.0.10.130:/mnt/store/internal/iris";
assert !(lib.any (lib.hasPrefix "x-systemd.idle-timeout") iris.fileSystems."/var/lib/hermes-backup".options);
assert iris.systemd.timers.hermes-backup.timerConfig.OnCalendar == "*-*-* 01:30";
assert lib.hasInfix "/var/lib/hermes-backup" iris.systemd.services.hermes-backup.script;
assert !(lib.hasInfix "cp -r /var/lib/hermes" iris.systemd.services.hermes-backup.script);
```

  plus an assert on the TrueNAS host's config that `nfsShares.iris.hosts == [ "10.0.10.101" ]`
  (use the attribute path the existing `nix-cache` share evaluates to).

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: TrueNAS**: `nfsShares.iris = { path = "/mnt/store/internal/iris"; hosts = [ "10.0.10.101" ]; };`
  with a comment like the `authentication` one (root squashed: dataset owner must be
  the `hermes` uid; pin `users.users.hermes.uid` in `hermes.nix` to a fixed value, e.g.
  `990`, and note it). Add the dataset where `datasets` are declared.
  `store/internal` is already in the `store` restic repo, so no change to
  `backup/homelab.nix` is needed unless `store/internal` children are listed one by
  one there: check, and drop that file from this task if so.

- [ ] **Step 4: `backup.nix`**: NFS mount (`nfsvers=4.2`, `x-systemd.automount`, no
  idle timeout, as `modules/server/cache/`), `hermes-backup` oneshot as user `hermes`,
  `RequiresMountsFor = /var/lib/hermes-backup`: `hermes backup` to a dated archive if
  the pinned version has it, else `sqlite3 .backup` of every `*.db` under
  `/var/lib/hermes` into a temp dir plus `tar --exclude='*.db*'` of the rest; keep the
  last 7 archives. Timer `OnCalendar = "*-*-* 01:30"`, `Persistent = true`.

- [ ] **Step 5: Run the test**, then the five evals. Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
git commit -m "feat(agent): nightly Hermes state copy to TrueNAS store/internal/iris" -- modules/server/agent/backup.nix modules/server/truenas/homelab.nix tests/agent.nix
```

### Task 5: Docs

**Files:**
- Create: `docs/agent.md`
- Modify: `AGENTS.md` (machine table, `modules/server/` category list: add `agent`)
- Modify: `docs/homelab.md` (inventory row for VM 101)
- Modify: `docs/vmids.md` (`100–109` row: name 101 iris)
- Modify: `docs/lodestar.md` (Tailscale policy: "iris additions (2026-11-…)")

- [ ] **Step 1: `docs/agent.md`**: what iris is; where config lives; the two manual
  logins (`sudo -u hermes -i hermes auth add openai-codex`, `sudo -u hermes -i claude`)
  and how to redo them on a re-auth message; changing the default model; how the bot
  decides who to answer; the dashboard (gate + `thijs` + `iris-dashboard` password);
  backups and restore (untar into `/var/lib/hermes` with the units stopped); the
  out-of-scope write-access idea.
- [ ] **Step 2: Other docs** as listed. AGENTS.md row:
  `| iris | Proxmox VM 101, Hermes Agent (Discord bot), dashboard agent.vanwaaij.com (docs/agent.md) | x86_64-linux | iris | servers |`.
- [ ] **Step 3: Commit**

```bash
git commit -m "docs(agent): iris runbook and inventory" -- docs/agent.md AGENTS.md docs/homelab.md docs/vmids.md docs/lodestar.md
```

### Task 6: Rollout (operations; every outward step needs Thijs's go-ahead)

Not code: do these in order, and ask before each one that changes something outside the
repo (1Password, Tailscale, Proxmox, Grafana, pushing).

- [ ] **Secrets**: Thijs creates `iris-discord`/`token` and `iris-openrouter`/`credential`.
  Generate `iris-dashboard` (`password` 24 chars, `secret` 32 random bytes base64) with
  `op … item create --vault Homelab`.
- [ ] **Grafana token**: as Grafana admin (`grafana-admin`), create service account
  `iris` with role Viewer and a token; store it as `iris-grafana`/`token`.
- [ ] **Tailscale policy** (API, `tailscale-policy-authkey`): `tag:iris` in `tagOwners`
  (owners `autogroup:admin`, `tag:nixos`); grant `tag:iris → svc:grafana` tcp:443;
  `nixos-manager → tag:iris` tcp:7461 (Lodestar agent); Service `agent` created and
  auto-approved for `tag:router`, in the Services grant for Thijs's devices.
- [ ] **Push and promote**: push `unstable` (ask), promote to `stable`
  (`lodestar promote --yes`), let the cache build iris.
- [ ] **VM**: on `pve`, `qm clone 9000 101 --name iris --full`, `qm set 101 --cores 4
  --memory 6144 --cpu host --onboot 1`, `qm resize 101 scsi0 40G`, start; install
  the iris system (template flow in `docs/lodestar.md` "enrolling a host"),
  `sudo opnix token set`, enrol in Lodestar.
- [ ] **Router**: rebuild router (route + Service), then `tailscale serve drain svc:agent`,
  wait, `advertise svc:agent`. Rebuild identity (gate group) and nixos-manager (link).
- [ ] **First start**: `systemctl status hermes-agent hermes-backend` active; with no
  logins yet, a DM from Thijs is answered via OpenRouter (Review Focus 5).
- [ ] **Logins**: Thijs runs the two login commands from `docs/agent.md`.
- [ ] **Success checks** (spec "Goal"): DM answered by the Codex model; "is prod
  healthy?" answered from Grafana; "write a script for X" runs Claude Code;
  `https://agent.vanwaaij.com` opens on a tailnet device after Kanidm + password;
  `curl -m5 https://agent.vanwaaij.com` from outside the tailnet fails;
  `curl -m5 http://10.0.10.101:9119` from prod is refused (Review Focus 2); a DM from
  another Discord account gets no answer (Review Focus 1); next morning an archive exists
  in `store/internal/iris` (Review Focus 4).
- [ ] **Memory**: add a project memory for iris (live date, open items).
