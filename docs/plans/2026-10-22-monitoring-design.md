# Homelab monitoring: design

One place that shows what the homelab is doing (uptime, resources, services, logs) and
tells Thijs when something breaks. Grafana with Prometheus and Loki on a new VM
`monitor`, an agent on every NixOS server, alerts through Healthchecks.io. Closes
finding #11 ("No monitoring or alerting") in `docs/homelab.md`.

Status: approved in conversation 2026-10-22 (all sections). Next: implementation plan.

## Goals

- One Grafana home page answers "is everything fine?": every machine up or down, its
  uptime, CPU, RAM and disk, failed systemd units, the state of every route, the latest
  errors from the logs.
- Drill-down dashboards per machine, per VM on pve, for TrueNAS, Traefik and containers.
- Logs of every NixOS server searchable in Grafana, with a **hard daily budget per
  machine** so one noisy host can't fill the disk.
- An alert reaches Thijs's phone when a machine, disk, unit, route or pool goes bad,
  and also when the monitor itself is gone.
- Declared as code like the rest: a new server, route or person shows up in monitoring
  without editing the monitoring module.

## Scope

In: the NixOS servers (router, prod, identity, nixos-manager, and monitor itself;
router-test turns its agent off, see B), the Proxmox host `pve` and TrueNAS (VM 130).

Out: workstations (hermes, hephaestus, atlas, apollo), the Rocky VMs (archipelago,
vpn; they join when they move to NixOS), the Hetzner server. Archipelago's public URL
is still probed (it is a route).

## Decisions

- **Prometheus + Loki + Grafana from nixpkgs' NixOS modules** (considered:
  VictoriaMetrics + VictoriaLogs, lighter but VictoriaLogs only caps disk globally, not
  per host; Grafana Cloud, data leaves the house). The community dashboards (Node
  Exporter Full, Proxmox, Traefik, cAdvisor) target this stack, and Loki has per-tenant
  limits that can be changed at runtime, which the log budget needs.
- **Own VM, 140 `monitor`** (considered: on nixos-manager). The 140 to 149 band is
  "Messaging & monitoring" in `docs/vmids.md`. A broken monitor doesn't take Lodestar or
  the builder down, and it watches nixos-manager from outside.
- **Tailnet only.** `grafana.vanwaaij.com` with `public = false`; metrics of the whole
  fleet are not for the internet.
- **Sign-in through Kanidm** (OIDC), like Immich and Lodestar. No local Grafana users
  besides the bootstrap admin (password in 1Password, for when Kanidm is down).
- **Alerts through Healthchecks.io**, already used for restic and the update timer.
  Healthchecks does the notifying (its integrations: phone app, email); Grafana only
  reports fail/success to checks.
- **Grafana-managed alerting**, no Alertmanager: one fewer service, rules provisioned
  from Nix.
- **Logs: one Loki tenant per machine** (`X-Scope-OrgID` = host name), so limits,
  budgets and retention are per machine.

## A. The monitor VM

| VMID | IP | Name | Size |
|---|---|---|---|
| 140 | 10.0.10.140 | monitor | 2 vCPU, 4 GB, 16 GB root (local-lvm) + 64 GB data disk (store-lvm) |

- Cloned from template 9000 like the other VMs (`docs/homelab.md`), `onboot`, `cpu: host`
  (opnix).
- `hosts/servers/monitor.nix`: thin, `type = "server"`, `fleet = true`,
  `tags = [ "tag:monitor" ]`, `netInterface.ip = "10.0.10.140"`,
  `homelab.monitoring.server.enable = true`.
- **Tailscale policy:** `tag:monitor` added to `tagOwners`, owned by `tag:nixos`
  (AGENTS.md gotcha), or the host cannot join.
- Data disk: ext4 labelled `monitor-data`, mounted at `/var/lib/monitoring`;
  Prometheus and Loki keep their state below it. Losing it loses history only, not
  configuration (all config is in Nix), so it is **not** backed up.
- Prometheus retention: 90 days or 20 GB, whichever comes first
  (`--storage.tsdb.retention.time`, `--storage.tsdb.retention.size`).

## B. Agent on every NixOS server

`modules/server/monitoring/agent.nix`, on for every server (`isServer`) unless
`homelab.monitoring.agent.enable = false` (default true; router-test sets it false so
the test twin doesn't page). It only opens ports to the monitor:
`networking.firewall.extraInputRules` / `interfaces` rules allowing `10.0.10.140` on the
exporter ports, nothing else.

- **node_exporter** (`services.prometheus.exporters.node`), collectors default +
  `systemd` (unit states, failed units) + `processes`. Port 9100.
- **Alloy** (`services.alloy`) reads the journal and pushes to Loki at
  `http://10.0.10.140:3100` with `X-Scope-OrgID = <hostname>` and labels `host`, `unit`,
  `priority`. Drops priority `debug` (7) at the source. Its own position file survives
  restarts, so a reboot doesn't resend.
- **Per-host extras**, declared next to the service they watch (inside that module's
  `mkIf`):
  - prod: **cAdvisor** (`services.cadvisor`, port 9101) for the Nextcloud, Jellyfin,
    Immich and database containers.
  - router: Traefik's own Prometheus metrics (`metrics.prometheus` on a separate
    entrypoint, port 8082, only to the monitor).
  - identity: Kanidm has no Prometheus endpoint; its health is the blackbox probe of
    `id.vanwaaij.com` (section D) plus its unit state from node_exporter.
- **Scrape targets are collected flake-wide**, the way routes are: a new data option
  `homelab.monitoring.targets.<name> = { port; path ? "/metrics"; }` on every host,
  set by the agent and the extras, and a `tools.monitoringTargetsFrom` that the monitor
  turns into Prometheus scrape configs (address = the host's `netInterface.ip`). A new
  server is monitored by being a server.

## C. Machines that aren't NixOS

- **pve** via **prometheus-pve-exporter** (`services.prometheus.exporters.pve`) running
  on the monitor, against `https://10.0.10.50:8006` with an API token for a user
  `monitoring@pve` with the role `PVEAuditor` (read-only). Token in 1Password
  `Homelab/pve-monitoring-token`, read with opnix. Gives per-VM up/down, CPU, RAM,
  disk and network, host CPU/RAM, and storage use (`local-lvm`, `store-lvm`). The user,
  role and token are created once by hand on pve (`pveum`), documented in
  `docs/monitoring.md`.
- **pve host details** (temperatures, NVMe wear) are out of scope for now: they need
  node_exporter on pve itself, which is not managed by this repo. Listed as a
  follow-up.
- **TrueNAS** via its built-in reporting exporter (Reporting → Exporters → Graphite) to a
  **graphite_exporter** on the monitor (`services.prometheus.exporters.graphite`, port
  9109) with a mapping file for pool, disk, ARC and network metrics. The exporter
  setting on TrueNAS is applied by `modules/server/truenas/` (the TrueNAS-as-code
  module on nixos-manager) if its API allows it, otherwise once by hand. Pool health
  (`ONLINE`/`DEGRADED`) comes from a small timer on the monitor that calls
  `pool.query` over the TrueNAS API (key in 1Password) and writes it as a textfile
  metric. SMART data stays with TrueNAS: its own alert service points at the
  Healthchecks check `truenas` (webhook), configured in the same place.

## D. Uptime of the routes

- **blackbox_exporter** on the monitor with an `http_2xx` module (follows redirects;
  a sign-in redirect to Kanidm counts as up, 5xx and timeouts count as down).
- Targets are every `homelab.routes` entry in the flake plus `homelab.router.extraRoutes`,
  collected with the existing `tools.routesFrom`: a new route is probed with no edit
  here. Probed over the LAN by name (the monitor uses the router's split DNS through the
  tailnet, like any other machine), so a probe goes through Traefik like a visitor.
  Routes with `passthrough` (Kanidm) are probed the same way (TLS is real).
- Probes every 60 s. Uptime % per route over 24 h / 7 d / 30 d on the home page.

## E. Logs and the daily budget per machine

- **Loki** single-binary (`services.loki`), multi-tenant (`auth_enabled: true`),
  filesystem storage under `/var/lib/monitoring/loki`, TSDB index, compactor with
  retention on. Listens on `10.0.10.140:3100`, firewall open only to the server IPs
  (from the flake's hosts).
- **Defaults per tenant** (Loki `limits_config`): retention **14 days**, ingestion rate
  1 MB/s with 4 MB burst (protects against floods within a day).
- **Budget per machine:** `homelab.monitoring.agent.logBudgetMB` on each host
  (default **200 MB/day**; prod may need more, set in its host file if the first week
  shows it). Collected flake-wide with the scrape targets.
- **Enforcement:** a timer on the monitor (`loki-budget`, every 5 minutes) reads per
  tenant `sum(increase(loki_distributor_bytes_received_total{tenant="<host>"}[24h]))`
  from Prometheus (Loki's own metrics are scraped). If a host is over its budget, the
  script writes an override for that tenant with `ingestion_rate_mb` near zero into
  Loki's **runtime config** file (`runtime_config.file`, reloaded every 10 s, no
  restart); once the 24 h window drops back under budget, the override is removed.
  Rejected lines are counted by Loki (`loki_discarded_samples_total`); Alloy drops them
  rather than buffering forever.
- **Upper bound on disk:** budget × retention per machine, e.g. 200 MB × 14 = 2.8 GB
  raw before compression, about 1 GB on disk. Five hosts fit easily in the 64 GB disk
  next to Prometheus.
- An alert fires when a host is cut off ("router hit its log budget"), so missing logs
  are never silent.

## F. Grafana

- `services.grafana` on the monitor, listening on `10.0.10.140:3000`.
- **Route:** `homelab.routes.grafana = { host = "grafana.vanwaaij.com"; backend =
  "http://10.0.10.140:3000"; public = false; }` in the monitoring module. Tailnet only;
  Tailscale Service `grafana`, split DNS as for every route.
- **Sign-in:** `homelab.access.grafana` with `members = [ "thijs" ]` and an `oidc`
  client (redirect `https://grafana.vanwaaij.com/login/generic_oauth`). Grafana's
  `auth.generic_oauth` against Kanidm, `role_attribute_path` maps people with
  `admin = true` in `people.nix` to `Admin` and every other member of `grafana-users` to
  `Viewer`. How the admin flag reaches the token (a second group `grafana-admins` in the
  `groups` claim, or a claim map) follows what `tools/accessType.nix` can express;
  if it can't, the access type gets a small extension, as Jellyfin's `AdminRoles` did. Login form off; the bootstrap admin
  (`Homelab/grafana-admin`) stays for when Kanidm is down. Client secret from
  1Password via opnix, like the other OIDC apps (exact mechanism follows what
  `docs/identity.md` does for Immich).
- **Lodestar link:** `lodestar.links.grafana`, group *Infrastructure*.
- **Provisioned from Nix** (`services.grafana.provision`): data sources Prometheus and
  Loki (one Loki data source per tenant is awkward; instead one data source with
  multi-tenant query header `X-Scope-OrgID: router|prod|identity|nixos-manager|monitor`,
  built from the flake's hosts; needs `multi_tenant_queries_enabled: true` in Loki),
  and dashboards as JSON files in
  `modules/server/monitoring/dashboards/`:
  - **Homelab overview** (home page, written here): one row per machine (up, uptime,
    CPU, RAM, root disk, failed units), pve storage gauges, TrueNAS pools, route status
    table with 24 h uptime, a logs panel of `priority <= err` from all hosts, firing
    alerts.
  - **Node Exporter Full** (grafana.com 1860), **Proxmox via Prometheus** (10347),
    **Traefik** (17346), **cAdvisor** (14282), **Loki logs** (a simple explorer per
    host/unit). Vendored as JSON with their data source references replaced; versions
    pinned by being files in the repo.
- Dashboards are read-only in the UI (`allowUiUpdates = false`); changes go through git.

## G. Alerts

Grafana-managed alert rules, provisioned from Nix (`services.grafana.provision.alerting`):

| Alert | Condition | For |
|---|---|---|
| Host down | `up{job="node"} == 0` | 3 min |
| VM down | pve exporter: a VM with `onboot` not running | 5 min |
| Disk almost full | any filesystem > 85 % (root, data disks, `local-lvm`, `store-lvm`) | 10 min |
| Failed unit | `node_systemd_unit_state{state="failed"} == 1` | 5 min |
| Route down | blackbox `probe_success == 0` | 3 min |
| TrueNAS pool | pool state not `ONLINE` | 1 min |
| Log budget hit | the budget override is active for a host | 0 |
| Memory pressure | available RAM < 10 % | 15 min |

- **Contact point:** a webhook to the Healthchecks check `homelab-alerts`
  (`https://hc-ping.com/<uuid>`), URL in 1Password `Homelab/healthchecks-homelab-alerts`.
  Firing must mark the check down and resolved must mark it up. Healthchecks supports
  keyword filters on the ping body (failure keyword `"status":"firing"`, success
  keyword `"status":"resolved"`); **verify at implementation** that this works for HTTP
  bodies on healthchecks.io. Fallback: a tiny relay on the monitor (a systemd socket
  service) that reads Grafana's JSON and calls `/<uuid>/fail` or `/<uuid>`.
- One check for all alerts means one notification per state change; the message
  (Grafana's summary in the ping body) says what fired, readable in the Healthchecks
  event log. Grouping: `group_by: [alertname, host]`, repeat every 4 h.
- **Watchdog:** a rule that always fires sends to a second contact point, the check
  `homelab-monitor-watchdog` (period 5 min, grace 5 min), repeated every minute. If the
  monitor, Grafana or its network dies, Healthchecks alerts on the missing pings.
- Healthchecks' own notification (phone app / email) is configured on healthchecks.io,
  as for the existing checks.

## H. Testing and rollout

- `nix eval` for every host (AGENTS.md list plus `monitor`), `nix flake check`.
- **NixOS VM test** in `tests/monitoring.nix`, run on nixos-manager: a `monitor` node
  and one agent node. Checks: Prometheus has `up{instance="agent"} == 1`; a journal
  line logged on the agent is found through Loki's query API within a minute; the
  budget timer with a 1 MB budget cuts the agent off after a burst of logs and the
  next line is rejected; Grafana answers on `/api/health` with the provisioned data
  sources and dashboards.
- **Rollout:**
  1. Tailscale policy: `tag:monitor` in `tagOwners`.
  2. 1Password items: `grafana-admin`, `grafana-oidc` (if not generated by
     provisioning), `pve-monitoring-token`, `truenas-monitoring-key`,
     `healthchecks-homelab-alerts`, `healthchecks-monitor-watchdog`; the two checks on
     healthchecks.io.
  3. pve: user `monitoring@pve`, role `PVEAuditor`, token; create VM 140 with its data
     disk; bootstrap the opnix token.
  4. Promote, apply `monitor`; check Grafana, data sources, pve and blackbox targets.
  5. Apply `identity` (OIDC client) and `router` (route, Tailscale Service).
  6. Agents one host at a time: nixos-manager, identity, router, prod. Check each in
     Prometheus and Loki before the next.
  7. TrueNAS exporter and alert service.
  8. Test an alert end to end (stop a unit on router-test with its agent temporarily
     on, or lower a threshold), and the watchdog (stop Grafana for 15 min).
  9. `docs/monitoring.md` (what runs, where, how to add a target, budgets, pve/TrueNAS
     manual steps), `docs/homelab.md` (VM 140, finding #11 closed), AGENTS.md machine
     table.

## Layout

```
modules/server/monitoring/
  options.nix          # homelab.monitoring.{agent,server,targets} options (all hosts)
  agent.nix            # node_exporter, Alloy, firewall to the monitor
  server.nix           # Prometheus, scrape configs from the flake
  loki.nix             # Loki, runtime config, budget timer
  grafana.nix          # Grafana, OIDC, route, access, Lodestar link, provisioning
  alerts.nix           # alert rules, contact points, watchdog
  exporters.nix        # pve, graphite (TrueNAS), blackbox, TrueNAS pool timer
  dashboards/*.json
tools/monitoringTargetsFrom.nix
hosts/servers/monitor.nix
tests/monitoring.nix
docs/monitoring.md
```

`options.nix` and `agent.nix` sit under `server/` and are gated on `isServer`;
everything else on `homelab.monitoring.server.enable`. The per-host extras (cAdvisor,
Traefik metrics) live in the prod service modules and the router module.

## Follow-ups (not in this design)

- node_exporter on pve itself (temperatures, NVMe wear, SMART of the NVMe).
- Monitoring the Rocky VMs and workstations.
- Lodestar showing Grafana's firing alerts in its Services tab.
- Pointing PVE's own notifications at Healthchecks.
