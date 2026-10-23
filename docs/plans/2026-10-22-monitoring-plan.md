# Homelab monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grafana, Prometheus and Loki on a new VM `monitor` (140), an agent on every NixOS
server, uptime probes for every route, a hard daily log budget per machine, and alerts
through Healthchecks.io.

**Architecture:** Data options on every host (`homelab.monitoring.*`) say what a host
exposes; a tool collects them flake-wide (like `tools.routesFrom`) and the monitor turns
them into scrape configs, Loki limits and firewall sources. Everything on the monitor is
gated on `homelab.monitoring.server.enable`; the agent on `isServer`. Secrets reach the
modules through path options whose defaults are opnix paths, so the VM test can swap them
for plain files.

**Tech Stack:** NixOS 26.05 modules (`services.prometheus`, `services.loki`,
`services.alloy`, `services.grafana`, `services.cadvisor`, exporters `node`, `pve`,
`graphite`, `blackbox`), bash + curl + jq for the two timers, opnix for secrets.

**Spec:** `docs/plans/2026-10-22-monitoring-design.md`

## Global Constraints

- Monitor: VMID 140, `10.0.10.140`, 2 vCPU, 4 GB, 16 GB root on local-lvm, 64 GB data disk on store-lvm labelled `monitor-data`, mounted at `/var/lib/monitoring`, tag `tag:monitor`, `fleet = true`.
- Prometheus retention 90 days or 20 GB. Loki retention 14 days, ingestion 1 MB/s, burst 4 MB, default budget 200 MB/day per machine, debug (priority 7) dropped at the source.
- Grafana: `grafana.vanwaaij.com`, `public = false`, backend `http://10.0.10.140:3000`; Kanidm client `grafana`, `members = [ "thijs" ]`, `preferShortUsername = true`, PKCE; `admins` group → `Admin`, else `Viewer`; auto-login to Kanidm, bootstrap admin `Homelab/grafana-admin` at `/login?disableAutoLogin`.
- Alerts: one Healthchecks check per rule, slug `homelab-<hc>`, `timeout = 31536000`, `filter_http_body = true`, `failure_kw = "\"status\":\"firing\""`, `success_kw = "\"status\":\"resolved\""`, `filter_default_fail = false`, `channels = "VWP BACKUP"` (was `"*"` until 2026-10-23, which also notified the Raika Discord); watchdog `homelab-watchdog` with timeout 300, grace 300, no filtering. `group_by: [alertname, host]`, group interval 1m, repeat 4h (watchdog 1m).
- Agent exporter ports are reachable from `10.0.10.140` only.
- Every module is always imported; folder matches condition (AGENTS.md). Platform gate `lib.optionalAttrs hostPlatform.isLinux` around the whole module, other gates `lib.mkIf`.
- No `//` on attrsets that share top-level keys; use `lib.mkMerge`.
- Format with the repo's nixfmt (AGENTS.md). New files `git add`ed before evaluating. Commit only own paths: `git commit -m "…" -- <paths>`, conventional style, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; author `Thijs van Waaij <thijs@vanwaaij.com>`. Don't push without asking.
- 1Password items (vault Homelab) are the contract: `grafana-admin` (fields `password`, `secret-key`: any long random string, Grafana's encryption key), `kanidm-oauth2-grafana` (`credential`), `pve-monitoring-token` (`env`: `PVE_USER=monitoring@pve`, `PVE_TOKEN_NAME=prometheus`, `PVE_TOKEN_VALUE=…`), `healthchecks-ping-key` (`env`: `HC_PING_KEY=…`), `healthchecks-api-key` (`credential`, read-write), `healthchecks-readonly-key` (`credential`), `healthchecks-project` (`uuid`), and the existing `truenas-automation` SSH key.

Deviation from the spec, decided here: TrueNAS pool health is read with `sudo midclt call pool.query` over SSH as `automation` (the same path `truenas-reconcile` uses; TrueNAS 26 has deprecated the REST API), so there is no `truenas-monitoring-key`. The TrueNAS Graphite exporter and the TrueNAS alert service are set once by hand (Task 10), not by `truenas-reconcile`.

## Review Focus

1. **A route that redirects to sign-in** (gated routes, Grafana itself): a probe must count it as up, not down. Test in Task 6: the blackbox module follows redirects and accepts 2xx after them.
2. **A host removed from the flake or with its agent off** (router-test): it must vanish from targets, Loki tenants and the Grafana tenant header, and must not page. Test in Task 1 (tool skips it) and Task 2 (router-test has no node exporter).
3. **The budget timer when Prometheus is down or returns no data**: it must leave the current overrides alone, not lift a block or block everyone. Test in Task 5 (script with an empty / failing query keeps the file unchanged).
4. **The Healthchecks free plan's 20-check limit**: `healthchecks-sync` must fail loudly on 403, not half-create. Test in Task 8 (script exits non-zero and names the check on a non-2xx).
5. **Alerts while Healthchecks or the internet is down**: Grafana retries; the watchdog check then goes down on Healthchecks' side, which is the wanted signal. No test; noted in `docs/monitoring.md` (Task 10).

---

### Task 1: Monitoring options and `tools.monitoringTargetsFrom`

**Files:**
- Create: `modules/server/monitoring/options.nix`
- Create: `tools/monitoringTargetsFrom.nix`
- Create: `tests/monitoring-targets-from.nix`
- Modify: `programs.nix` (add `checks.x86_64-linux.monitoring-targets-from`, same shape as `routes-from`)
- Modify: `AGENTS.md` (tools list in "Layout")

**Interfaces:**
- Produces options (on every host, plain data unless noted):
  - `homelab.monitoring.serverAddress : str`, default `"10.0.10.140"`.
  - `homelab.monitoring.agent.enable : bool`, default `hostPlatform.isServer` (false on darwin/workstations).
  - `homelab.monitoring.agent.logBudgetMB : ints.positive`, default `200`.
  - `homelab.monitoring.targets : attrsOf (submodule { port : port; path : str = "/metrics"; })`, default `{ }`.
  - `homelab.monitoring.server.enable : bool`, default `false`.
- Produces `tools.monitoringTargetsFrom { inherit lib; } { nixosConfigurations } → attrsOf { address : str; logBudgetMB : int; targets : attrsOf { port; path; }; declaredBy : str; }`, keyed by configuration name; only configurations with the option, `agent.enable = true` and a non-null `homelab.lan.address`.

- [ ] **Step 1: Write the failing eval check** `tests/monitoring-targets-from.nix`, modelled on `tests/routes-from.nix` (stub configs from `options.nix` + `modules/server/homelab/lan.nix`, `specialArgs = { tools; hostPlatform = { isServer = true; isLinux = true; }; serverOptions = { netInterface.ip = …; }; }`). Asserts:
  - `r.alpha.address == "10.0.10.1"`, `r.alpha.logBudgetMB == 200`, `r.alpha.targets.node.port == 9100`, `r.alpha.targets.node.path == "/metrics"`.
  - A stub with `agent.enable = false` is absent (Review Focus 2).
  - A stub without the option is skipped; a stub with `lan.address = null` is absent.
- [ ] **Step 2: Run, expect failure:** `nix eval .#checks.x86_64-linux.monitoring-targets-from.drvPath` → error, `monitoringTargetsFrom` missing.
- [ ] **Step 3: Implement** `options.nix` (no `optionalAttrs`: data options exist on every platform; descriptions in the style of `routes-option.nix`) and the tool (header comment like `routesFrom.nix`).
- [ ] **Step 4: Run, expect a drv path.** Then evaluate all five hosts from AGENTS.md "Verifying changes".
- [ ] **Step 5: Format, commit** `feat(monitoring): options and tools.monitoringTargetsFrom`.

### Task 2: Agent on every server (node_exporter, Alloy, firewall)

**Files:**
- Create: `modules/server/monitoring/agent.nix`
- Create: `tests/monitoring.nix` (eval check on real hosts, grows in later tasks; shape of `tests/router.nix`)
- Modify: `programs.nix` (`checks.x86_64-linux.monitoring`)
- Modify: `hosts/servers/router-test.nix` (`homelab.monitoring.agent.enable = false;` with a one-line comment)

**Interfaces:**
- Consumes: Task 1 options.
- Produces: on every agent host `homelab.monitoring.targets.node = { port = 9100; }`; node_exporter textfile directory `/var/lib/node-exporter-textfile` (later tasks write `*.prom` there); Alloy pushes to `http://${serverAddress}:3100/loki/api/v1/push` with header `X-Scope-OrgID = config.networking.hostName` and labels `host`, `unit`, `priority`.

- [ ] **Step 1: Failing assertions in `tests/monitoring.nix`:**
  - prod: `services.prometheus.exporters.node.enable`, `enabledCollectors` contains `"systemd"` and `"processes"`, `extraFlags` contains `--collector.textfile.directory=/var/lib/node-exporter-textfile`.
  - prod: `services.alloy.enable`; the rendered Alloy config (`environment.etc."alloy/config.alloy".text`) contains `X-Scope-OrgID`, `"prod"`, `10.0.10.140:3100`, and a drop for priority `7`.
  - prod: `networking.firewall.extraCommands` contains `-s 10.0.10.140` and `--dport 9100`; `9100` is **not** in `networking.firewall.allowedTCPPorts` nor in any `interfaces.*.allowedTCPPorts`.
  - router-test: `!services.prometheus.exporters.node.enable`, `!services.alloy.enable` (Review Focus 2).
  - atlas is not touched (darwin: options exist, nothing else).
- [ ] **Step 2: Run** `nix eval .#checks.x86_64-linux.monitoring.drvPath` → assertion failure.
- [ ] **Step 3: Implement `agent.nix`**: `lib.optionalAttrs hostPlatform.isLinux { config = lib.mkIf cfg.agent.enable { … }; }`. Firewall: iptables rules in `extraCommands` (`iptables -A nixos-fw -p tcp -s <serverAddress> --dport <port> -j nixos-fw-accept` for every port in `homelab.monitoring.targets`) and matching `extraStopCommands` deletes. Alloy: `loki.source.journal` → `loki.process` (`stage.drop` on `priority == "7"`) → `loki.write` with `tenant_id`.
- [ ] **Step 4: Run check, evaluate all five hosts.**
- [ ] **Step 5: Format, commit** `feat(monitoring): agent on every server`.

### Task 3: Per-host extras (cAdvisor on prod, Traefik metrics on router)

**Files:**
- Modify: `modules/server/services/docker.nix` (cAdvisor inside its existing `mkIf`; read it first to find the condition that means "this host runs the containers")
- Modify: `modules/server/homelab/router/default.nix` (static config)
- Modify: `tests/monitoring.nix`

**Interfaces:**
- Produces: prod `homelab.monitoring.targets.cadvisor = { port = 9101; }`; router `homelab.monitoring.targets.traefik = { port = 8082; }`.

- [ ] **Step 1: Failing assertions:** prod `services.cadvisor.enable`, `services.cadvisor.port == 9101`, `listenAddress == "0.0.0.0"`, target `cadvisor` present; router `staticConfigOptions.metrics.prometheus.entryPoint == "metrics"`, `entryPoints.metrics.address == ":8082"`, target `traefik` present; firewall `extraCommands` on each contains its port with `-s 10.0.10.140`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** (comment each with one line naming the dashboard that reads it).
- [ ] **Step 4: Run check; the existing `checks.x86_64-linux.router` must still evaluate.**
- [ ] **Step 5: Commit** `feat(monitoring): cadvisor on prod, traefik metrics on the router`.

### Task 4: Monitor host and Prometheus

**Files:**
- Create: `hosts/servers/monitor.nix` (thin, like `identity.nix`; comment pointing at `modules/server/monitoring/`)
- Create: `modules/server/monitoring/secrets.nix`
- Create: `modules/server/monitoring/server.nix`
- Modify: `tests/monitoring.nix`

**Interfaces:**
- Consumes: `tools.monitoringTargetsFrom`.
- Produces:
  - `homelab.monitoring.server.hosts : attrsOf …` (the tool's result type), default: the flake's (`inputs.self.nixosConfigurations` with this configuration's own `config` substituted, exactly as `fromFlake` in `modules/server/identity/kanidm.nix`). The VM test overrides it.
  - `homelab.monitoring.server.secrets.<name> : nullOr path` for `grafanaAdminPassword`, `grafanaOidcSecret`, `pveEnv`, `healthchecksPingEnv`, `healthchecksApiKey`, `healthchecksReadonlyKey`, `healthchecksProject`, `truenasKey`. `secrets.nix` declares the opnix secrets (references in Global Constraints, owners per consuming service) and sets these to `secretPaths.*` with `lib.mkDefault`. Later tasks read only these options.
  - `homelab.monitoring.server.{pve,truenas,healthchecks}.enable : bool`, default `true` (the VM test turns them off).
  - Prometheus on `127.0.0.1:9090` (only Grafana and the timers on the monitor use it), `stateDir` under `/var/lib/monitoring`; job `node`/`cadvisor`/`traefik` etc. named after the target key, one static target per host `<address>:<port>` with label `host = <name>`.
  - `fileSystems."/var/lib/monitoring" = { device = "/dev/disk/by-label/monitor-data"; fsType = "ext4"; options = [ "nofail" ]; }`.

- [ ] **Step 1: Failing assertions** on `nixosConfigurations.monitor`: `services.prometheus.enable`; retention flags `--storage.tsdb.retention.time=90d` and `--storage.tsdb.retention.size=20GB`; a scrape config `node` whose targets include `10.0.10.100:9100` with label `host = "prod"` and `10.0.10.140:9100`; no target for `router-test`; job `cadvisor` has exactly prod; `fileSystems."/var/lib/monitoring".device`.
- [ ] **Step 2: Run, expect failure** (no `monitor` host yet).
- [ ] **Step 3: Implement** host file, `secrets.nix`, `server.nix`. No firewall port for Prometheus.
- [ ] **Step 4: Run check and evaluate** `nixosConfigurations.monitor.config.system.build.toplevel.drvPath` plus all five hosts.
- [ ] **Step 5: Commit** `feat(monitoring): monitor host and prometheus`.

### Task 5: Loki and the daily log budget

**Files:**
- Create: `modules/server/monitoring/loki.nix`
- Create: `modules/server/monitoring/loki-budget.sh`
- Create: `tests/loki-budget.sh` (shell test, runs on atlas without Nix services)
- Modify: `tests/monitoring.nix`

**Interfaces:**
- Consumes: `server.hosts` (addresses for the firewall, names for tenants, `logBudgetMB`).
- Produces: Loki on `:3100`, `auth_enabled: true`, `limits_config.multi_tenant_queries_enabled: true`, `retention_period: 336h`, `ingestion_rate_mb: 1`, `ingestion_burst_size_mb: 4`, `runtime_config.file = /var/lib/monitoring/loki/runtime.yaml`, `period: 10s`; Prometheus job `loki` scraping `127.0.0.1:3100`. Textfile metric on the monitor: `loki_budget_exceeded{tenant="<host>"} 0|1` in `/var/lib/node-exporter-textfile/loki-budget.prom`.
- `loki-budget.sh` contract — env: `PROM_URL`, `BUDGETS` (JSON `{ "<host>": <MB> }`), `RUNTIME_FILE`, `TEXTFILE`. Queries `sum by (tenant) (increase(loki_distributor_bytes_received_total[24h]))`; for each host over `MB × 1024²` writes `overrides.<host>: { ingestion_rate_mb: 0, ingestion_burst_size_mb: 0 }` (zero rate and burst reject every push; 0.0001 let ~100-byte lines through, found by the Task 9 VM test); writes both files atomically (temp + `mv`).

- [ ] **Step 1: Failing shell test** `tests/loki-budget.sh`, using a tiny `python3 -m http.server`-free stub: a fake `curl` on `PATH` that prints a fixture JSON. Cases:
  - router at 250 MB with budget 200 → runtime file has `overrides:` with `router:` and `ingestion_rate_mb: 0`; textfile has `loki_budget_exceeded{tenant="router"} 1` and `{tenant="prod"} 0`.
  - everyone under budget → runtime file has `overrides: {}`; all textfile values `0`.
  - curl fails (exit 7) or returns `"status":"error"` or an empty `result` while the file holds a block → the script exits non-zero and **both files are unchanged** (Review Focus 3).
- [ ] **Step 2: Run** `bash tests/loki-budget.sh` → fails (script missing).
- [ ] **Step 3: Implement** `loki-budget.sh` (style of `restic-truenas.sh`: `set -euo pipefail`, header comment) and `loki.nix`: `services.loki` with the config above, storage under `/var/lib/monitoring/loki`, compactor `retention_enabled`; `writeShellApplication` wrapping the script (`runtimeInputs = [ curl jq ]`), `systemd.services.loki-budget` + timer `OnCalendar=*:0/5`; firewall `extraCommands` accepting `:3100` from each host address in `server.hosts`.
- [ ] **Step 4: Run** `bash tests/loki-budget.sh` (passes) and add eval assertions: Loki settings above, timer present, `extraCommands` contains `-s 10.0.10.100` and `--dport 3100`, and `BUDGETS` contains `"prod":200`.
- [ ] **Step 5: Commit** `feat(monitoring): loki with a daily log budget per machine`.

### Task 6: Exporters on the monitor (pve, TrueNAS, blackbox, Healthchecks)

**Files:**
- Create: `modules/server/monitoring/exporters.nix`
- Create: `modules/server/monitoring/graphite-mapping.yaml`
- Create: `modules/server/monitoring/truenas-pools.sh`
- Modify: `tests/monitoring.nix`

**Interfaces:**
- Consumes: `server.secrets.{pveEnv,truenasKey,healthchecksReadonlyKey,healthchecksProject}`, `tools.routesFrom` (with `homelab.router.extraRoutes` of the router configuration, the way `modules/server/homelab/router/default.nix` collects them).
- Produces Prometheus jobs: `pve` (exporter on `127.0.0.1:9221`, target `10.0.10.50`, `module=default`), `truenas` (graphite_exporter `:9109`, Graphite input `:9109/udp+tcp` on 2003 from `10.0.10.130` only), `blackbox` (exporter `127.0.0.1:9115`, one target per route `https://<route.host>/`, label `route = <name>`), `healthchecks` (`https://healthchecks.io/projects/<uuid>/metrics/`, `authorization.credentials_file`, interval 2m). Textfile metric `truenas_pool_healthy{pool="<name>"} 0|1` from `truenas-pools` (timer every 5 min, `sudo midclt call pool.query` over SSH as `automation@10.0.10.130`, known host from `config.truenas.hostKey`'s value).

- [ ] **Step 1: Failing assertions:**
  - blackbox config module `http_2xx`: `prober = "http"`, `http.follow_redirects = true`, `valid_status_codes = [ ]` (2xx) (Review Focus 1); targets include `https://nextcloud.vanwaaij.com/`, `https://id.vanwaaij.com/`, `https://grafana.vanwaaij.com/` (after Task 7) and `https://ap.vanwaaij.com/`; none contains `test`.
  - `services.prometheus.exporters.pve.enable`, `environmentFile` set; job `pve` exists.
  - graphite exporter `mappingSettings` file is `graphite-mapping.yaml`; firewall allows 2003 from `10.0.10.130` only.
  - with `homelab.monitoring.server.truenas.enable = false` (via `extendModules`) there is no `truenas` job and no `truenas-pools` timer.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** The Graphite mapping covers TrueNAS's netdata-style names for pool usage, disk I/O and temperature, ARC size/hit ratio and interface traffic; confirm names against what TrueNAS actually sends during Task 10 and adjust the file then.
- [ ] **Step 4: Run check and evaluate monitor + five hosts.**
- [ ] **Step 5: Commit** `feat(monitoring): pve, truenas, blackbox and healthchecks exporters`.

### Task 7: Grafana (Kanidm sign-in, route, data sources, dashboards)

**Files:**
- Create: `modules/server/monitoring/grafana.nix`
- Create: `modules/server/monitoring/dashboards/{overview,node-exporter-full,proxmox,traefik,cadvisor,logs}.json`
- Create: `modules/server/identity/branding/icons/grafana.svg`
- Modify: `tests/monitoring.nix`, `tests/identity.nix` (grafana client in the provision state of `identity`)

**Interfaces:**
- Consumes: `server.secrets.{grafanaAdminPassword,grafanaOidcSecret}`, `server.hosts` (tenant header).
- Produces: data source uids `prometheus` and `loki` (Task 8 uses them); `homelab.routes.grafana`, `homelab.access.grafana`, `lodestar.links.grafana` (group *Infrastructure*).

- [ ] **Step 1: Failing assertions:**
  - monitor `services.grafana.settings`: `server.http_addr = "0.0.0.0"`, `http_port = 3000`, `root_url = "https://grafana.vanwaaij.com/"`; `auth.generic_oauth.auto_login = true` and no `disable_login_form`; `"auth.generic_oauth"` has `client_id = "grafana"`, `use_pkce = true`, `auth_url = "https://id.vanwaaij.com/ui/oauth2"`, `token_url = "https://id.vanwaaij.com/oauth2/token"`, `api_url = "https://id.vanwaaij.com/oauth2/openid/grafana/userinfo"`, `role_attribute_strict = true`, `role_attribute_path` mentions `admins`; `client_secret` and `security.admin_password` are `$__file{…}` strings.
  - Loki data source `jsonData.httpHeaderName1 = "X-Scope-OrgID"`, `secureJsonData.httpHeaderValue1 = "identity|monitor|nixos-manager|prod|router"` (sorted host names; no `router-test`).
  - dashboards provider `allowUiUpdates = false`, path is the `dashboards` directory; `overview.json` is the home dashboard (`settings.dashboards.default_home_dashboard_path`).
  - route `grafana`: `host = "grafana.vanwaaij.com"`, `backend = "http://10.0.10.140:3000"`, `public = false`.
  - `tests/identity.nix`: identity's provision state has `systems.oauth2.grafana` with `preferShortUsername = true` and origin `https://grafana.vanwaaij.com/login/generic_oauth`, and group `grafana-users` with `thijs`.
- [ ] **Step 2: Run both checks, expect failure.**
- [ ] **Step 3: Implement.** `role_attribute_path`: `(contains(groups[*], 'admins@id.vanwaaij.com') || contains(groups[*], 'admins')) && 'Admin' || 'Viewer'` (both forms until Task 10 confirms which Kanidm sends). Vendored dashboards (grafana.com 1860, 10347, 17346, 14282) with `${DS_*}` inputs replaced by the uids; `overview.json` written here per spec section F (rows per host from `label_values(up{job="node"}, host)`, pve storage, TrueNAS pools, route table with `avg_over_time(probe_success[24h])`, Healthchecks `hc_check_up`, logs panel `{priority=~"[0-3]"}`, alert list). Port 3000 open to the router's LAN address only (firewall rule).
- [ ] **Step 4: Run checks; evaluate monitor, identity, router and the five hosts.**
- [ ] **Step 5: Commit** `feat(monitoring): grafana with kanidm sign-in and dashboards`.

### Task 8: Alerts and Healthchecks sync

**Files:**
- Create: `modules/server/monitoring/alerts.nix`
- Create: `modules/server/monitoring/healthchecks-sync.sh`
- Create: `tests/healthchecks-sync.sh`
- Modify: `tests/monitoring.nix`

**Interfaces:**
- Consumes: data source uids `prometheus`, `loki`; `server.secrets.{healthchecksPingEnv,healthchecksApiKey}`; textfile metrics `loki_budget_exceeded`, `truenas_pool_healthy`.
- Produces: alert rules with label `hc` ∈ `host-down vm-down disk-full failed-unit route-down truenas-pool log-budget memory` and the watchdog (`hc = "watchdog"`); one contact point per `hc` with URL `https://hc-ping.com/$HC_PING_KEY/homelab-<hc>` (Grafana interpolates env vars in provisioning; `systemd.services.grafana.serviceConfig.EnvironmentFile = healthchecksPingEnv`).
- `CHECKS` also holds `truenas` (`filter = false`, timeout 31536000, no rule or contact point): TrueNAS's own alert service posts to its `/fail` URL (Task 10).
- `healthchecks-sync.sh` contract — env: `HC_API_KEY_FILE`, `CHECKS` (JSON list of `{ slug, name, timeout, grace, filter }`). For each: `POST https://healthchecks.io/api/v3/checks/` with `X-Api-Key`, `unique: ["slug"]`, `tags: "homelab monitoring"`, `channels: $HC_CHANNELS` ("VWP BACKUP"), and when `filter`: the keyword fields from Global Constraints. Exit non-zero naming the slug on any status other than 200/201.

- [ ] **Step 1: Failing shell test** `tests/healthchecks-sync.sh` with a fake `curl` recording request bodies: two checks → two POSTs; the alert check's body has `filter_http_body: true`, `failure_kw: "\"status\":\"firing\""`, `timeout: 31536000`; the watchdog's has `timeout: 300` and no `failure_kw`; a fake 403 on the second → exit non-zero and stderr names `homelab-watchdog` (Review Focus 4).
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** script + `alerts.nix`: rules per spec section G table (exprs: `up{job="node"} == 0` for 3m; `pve_up{id=~"qemu/.*"} == 0 and on(id) pve_onboot_status == 1` for 5m; `1 - node_filesystem_avail_bytes{fstype!~"tmpfs|nfs.*"} / node_filesystem_size_bytes > 0.85` and `pve_disk_usage_bytes / pve_disk_size_bytes > 0.85` for storages, 10m; `node_systemd_unit_state{state="failed"} == 1` 5m; `probe_success == 0` 3m; `truenas_pool_healthy == 0` 1m; `loki_budget_exceeded == 1` 0m; `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10` 15m; watchdog `vector(1)`), policy tree routing on `hc` with the grouping from Global Constraints; `systemd.services.healthchecks-sync` (oneshot, `after = network-online`, `restartTriggers` on the JSON) with `CHECKS` built from the same rule list, so rules and checks can't drift.
- [ ] **Step 4: Run** `bash tests/healthchecks-sync.sh` and the eval check (assert 9 contact points, each URL ends in `homelab-<hc>`, watchdog repeat interval `1m`, every rule has an `hc` label that has a contact point).
- [ ] **Step 5: Commit** `feat(monitoring): alert rules to healthchecks.io`.

### Task 9: VM test

**Files:**
- Create: `tests/monitoring-vm.nix`
- Modify: `programs.nix` (`checks.x86_64-linux.monitoring-vm = pkgs.testers.runNixOSTest (import ./tests/monitoring-vm.nix { … })`)

**Interfaces:**
- Consumes: all `modules/server/monitoring/*.nix` imported directly into test nodes with `node.specialArgs = { tools; hostPlatform = { isLinux = true; isDarwin = false; isServer = true; }; inputs = { self.nixosConfigurations = { }; }; serverOptions = { }; }` plus `modules/server/homelab/{lan,routes-option,access-option}.nix` and a stub `lodestar.links` option.

- [ ] **Step 1: Write the test.** Nodes `monitor` (`server.enable`, `pve/truenas/healthchecks.enable = false`, `server.hosts` set by hand to `{ agent = { address = <agent ip>; logBudgetMB = 1; targets.node = { port = 9100; path = "/metrics"; }; }; monitor = …; }`, secrets as `pkgs.writeText` files, Grafana OIDC pointed at a dummy URL) and `agent` (`serverAddress` = monitor's test IP). Script:
  - `monitor.wait_for_unit("prometheus")`, then within 120 s `curl -s 'localhost:9090/api/v1/query?query=up{host="agent",job="node"}'` has value `"1"`.
  - `agent.succeed("logger -t mtest hello-monitoring")`; within 60 s `curl -H 'X-Scope-OrgID: agent' 'localhost:3100/loki/api/v1/query_range?query={host="agent"} |= "hello-monitoring"'` returns a result.
  - `agent.succeed("head -c 3000000 /dev/urandom | base64 | logger -t flood")`; `monitor.succeed("systemctl start loki-budget")`; runtime file contains `agent:`; `loki_budget_exceeded{tenant="agent"} 1` in the textfile; a new line `after-budget` is not found after 30 s.
  - `curl -s localhost:3000/api/health` returns `"database": "ok"`; `/api/datasources` (basic auth with the test admin password via `?disableAutoLogin`) (basic auth with the test admin password) lists uids `prometheus` and `loki`.
  - From `agent`: `curl --max-time 3 <monitor>:9090` fails (closed), and from a third node `other`: `curl <agent>:9100/metrics` fails while `monitor` succeeds.
- [ ] **Step 2: Evaluate** `nix eval .#checks.x86_64-linux.monitoring-vm.drvPath` on atlas.
- [ ] **Step 3: Build on nixos-manager** (AGENTS.md "Linux builder", bundle of the branch): `nix build --no-link -L .#checks.x86_64-linux.monitoring-vm`. Expected: test passes. Fix modules, not the test, on failure.
- [ ] **Step 4: Also build** `.#nixosConfigurations.monitor.config.system.build.toplevel` there.
- [ ] **Step 5: Commit** `test(monitoring): vm test for scrape, logs, budget and grafana`.

### Task 10: Rollout and docs

Manual, ordered; each step ends with its check. Ask before pushing; servers apply through Lodestar after promote (`docs/lodestar.md`).

**Files:**
- Create: `docs/monitoring.md` (what runs where, adding a target, budgets and how to raise one, the manual pve/TrueNAS/Healthchecks steps below, behaviour when Healthchecks is unreachable: Review Focus 5)
- Modify: `docs/homelab.md` (VM 140 row and section, finding #11 → fixed), `docs/vmids.md` if it lists VMs, `docs/lodestar.md` (grants), `AGENTS.md` (machine table, `monitoring` in the `server/` category list), `docs/identity.md` (Grafana row in the app table)

- [ ] **Step 1: Tailscale policy** (API, `tailscale-policy-authkey`): `tagOwners` `tag:monitor` owned by `autogroup:admin` and `tag:nixos`; grants `tag:monitor` → `tag:router` port 53, `tag:monitor` → every `svc:*` tcp:443 (probes, Kanidm), `nixos-manager` → `tag:monitor` tcp:7461; Service `grafana` granted to the same sources as the other Services, auto-approved for `tag:router`. Check: policy GET shows them.
- [ ] **Step 2: 1Password items** from Global Constraints (`grafana-admin` needs both `password` and `secret-key`); Healthchecks: read-write and read-only API keys, ping key and project UUID from Project Settings. Count existing checks: existing + 10 ≤ 20 (free plan).
- [ ] **Step 3: pve:** `pveum user add monitoring@pve`, `pveum acl modify / --users monitoring@pve --roles PVEAuditor`, `pveum user token add monitoring@pve prometheus --privsep 0`; clone template 9000 to VM 140 (sizes in Global Constraints, `cpu: host`, `onboot 1`), add the data disk, format `mkfs.ext4 -L monitor-data`; first boot, `sudo opnix token set`. Check: `ssh -J pve monitor@10.0.10.140 true`.
- [ ] **Step 4: Push (after asking), promote, apply `identity`;** `scripts/kanidm-oauth2-secret.sh grafana`. Check: item `kanidm-oauth2-grafana` exists.
- [ ] **Step 5: Apply `monitor` with Healthchecks off, then `router`.** First set `homelab.monitoring.server.healthchecks.enable = false` in the monitor's host file (commit, promote). Without agents there is nothing to alert on yet, and with it on the Watchdog and `host-down` checks would page before the agents exist. Apply `monitor`, then `router`; on the router `tailscale serve drain svc:grafana` / `advertise svc:grafana`. Check: sign in at `https://grafana.vanwaaij.com` as thijs lands as Admin (decode the ID token once to see the `groups` form; drop the unused branch of `role_attribute_path`); Prometheus targets `pve` and `blackbox` up.
- [ ] **Step 6: Agents one host at a time** — apply nixos-manager, identity, router, prod; after each, `up{host="<name>"} == 1` and its logs in Grafana Explore. Check Grafana is reachable only through the router (`curl` to `10.0.10.140:3000` from another LAN host times out).
- [ ] **Step 7: Prepare, then enable Healthchecks.** Before flipping the flag:
  - `probe_success` is 1 for every route in Prometheus (`probe_success == 0` must be empty). A route whose `/` is not 2xx after redirects gets a probe path (route option or `extraRoutes` entry) first.
  - `qm config <id>` on `pve` for every VM that is often stopped (router-test 230, the Rocky VMs): `onboot`. Only hosts with the agent enabled are alerted on, but a VM that is stopped by design must not carry an agent or must be excluded from `host-down`.
  - Healthchecks' metrics endpoint accepts the Bearer form: `curl -H "Authorization: Bearer <read-only key>" https://healthchecks.io/projects/<uuid>/metrics/` returns 200 with `hc_check_up` lines (the form the `healthchecks` job uses).
  Then remove `healthchecks.enable = false` (commit, promote, apply `monitor`). Check: `healthchecks-sync` succeeded (it fails loudly if the response lacks the filter fields) and the checks exist; target `healthchecks` up; the Watchdog check is up.
- [ ] **Step 8: TrueNAS by hand:** Reporting -> Exporters -> Graphite to `10.0.10.140:2003`; Alerts -> Alert Services -> a Webhook to `https://hc-ping.com/<ping-key>/homelab-truenas/fail` (the check comes from `healthchecks-sync`; every TrueNAS alert counts as a failure, and after fixing the cause the check is set up again with a plain ping by hand, written down in `docs/monitoring.md`). Check `truenas_*` metrics and fix `graphite-mapping.yaml` names; commit that as `fix(monitoring): truenas graphite names`.
- [ ] **Step 9: End-to-end alert (mandatory, it proves the filter fields work on the real Healthchecks):** set `homelab.monitoring.agent.enable = true` on router-test temporarily (not committed; `nixos-rebuild test` on it), `systemctl start` a unit that fails -> Healthchecks `homelab-failed-unit` goes down and notifies, then resolves after fixing (the resolved webhook must flip it back up; if it stays down the filter is not working). Watchdog: `systemctl stop grafana` on the monitor for 12 min -> `homelab-watchdog` goes down; start it again.
- [ ] **Step 10: Write the docs above; commit** `docs(monitoring): rollout, operations and inventory`. Update memory note `homelab-front-door` leftovers if #11 was listed there.
