# Monitoring: Grafana, Prometheus, Loki, alerts

What watches the homelab, where it runs, and how to change it. Design:
`docs/plans/2026-10-22-monitoring-design.md`; plan and rollout:
`docs/plans/2026-10-22-monitoring-plan.md`. Live since 2026-10-23.

## What runs where

- **monitor** (VM 140, `10.0.10.140`, `hosts/servers/monitor.nix`, tag `tag:monitor`,
  Lodestar agent): Prometheus (`127.0.0.1:9090`, 90 days or 20 GB), Loki (`:3100`,
  one tenant per machine, 14 days), Grafana (`:3000`), and the exporters that watch
  machines without an agent. Prometheus and Loki keep their data on a second disk
  (`store-lvm`, label `monitor-data`, mounted at `/var/lib/monitoring`); it isn't backed
  up (history only, all config is in Nix). Without that disk Prometheus and Loki don't
  start (`RequiresMountsFor`) rather than filling the root disk.
- **Every NixOS server** (`modules/server/monitoring/agent.nix`, off on router-test):
  node_exporter (`:9100`, with the systemd collector) and Alloy shipping the journal to
  Loki (debug lines dropped, 1 h backfill after a restart). Docker hosts also run
  cAdvisor (`:9101`); the router exposes Traefik's metrics on `:8082`. These ports
  accept the monitor only (iptables rules from `homelab.monitoring.targets`).
- **On the monitor, for machines without an agent:**
  - Proxmox: prometheus-pve-exporter against `10.0.10.50:8006` as `monitoring@pve`
    (role `PVEAuditor`, token in 1Password `pve-monitoring-token`; certificate
    verification off, the API's certificate is self-signed).
  - TrueNAS: its Graphite exporter (Reporting → Exporters, `monitor`:
    `10.0.10.140:2003`, prefix and namespace `truenas`, every 10 s) into
    graphite_exporter; the names are mapped in
    `modules/server/monitoring/graphite-mapping.yaml` (everything else netdata sends is
    dropped). Pool health comes from `truenas-pools` (every 5 minutes,
    `midclt call pool.query` over SSH as `automation`).
  - Uptime: blackbox_exporter probes `https://<host>/` of every route in the flake
    (`homelab.routes` and the router's `extraRoutes`), so a new route is probed
    without editing anything here. A redirect to the sign-in page counts as up.
  - Healthchecks.io's own metrics (`hc_check_up`) for the existing checks.

## Grafana

`https://grafana.vanwaaij.com`, tailnet only (Tailscale Service `grafana` on the
router). Normal visits go straight to Kanidm; members of `grafana-users` get in,
people with `admin = true` in `people.nix` as Admin, the rest as Viewer. Break-glass
when Kanidm is down: user `admin` at `/login?disableAutoLogin`, password in 1Password
`grafana-admin`.

Dashboards are files in `modules/server/monitoring/dashboards/` and read-only in the
UI; change them in git. **Homelab overview** is the home page (machines and routes
up/down over time, then graphs per area, per-machine detail in the collapsed rows at
the bottom); the others are vendored from grafana.com (Node Exporter Full 1860,
Proxmox 10347, Traefik 17346, cAdvisor 14282) plus a log explorer.

## Logs and the daily budget

Each machine is a Loki tenant. `homelab.monitoring.agent.logBudgetMB` (default 200)
is its budget per 24 h. Every 5 minutes `loki-budget` sums the bytes Loki *accepted*
per machine over the last 24 h; over budget, it gives that tenant a zero ingestion
rate in Loki's runtime config (no restart), and lifts it once the machine is below
90 % of its budget. While blocked, the machine's logs are dropped and the
`log-budget` alert is firing. Raise a budget in the host file
(`options.homelab.monitoring.agent.logBudgetMB = 400;`). The real daily ceiling is a
little above the budget (up to 5 minutes at 1 MB/s before the next check).

## Alerts

Grafana's alert rules (`modules/server/monitoring/alerts.nix`) each report to their
own Healthchecks.io check, `homelab-<rule>`: `host-down`, `vm-down` (VMs with
`onboot`), `disk-full` (> 85 %, also Proxmox storage), `failed-unit`, `route-down`,
`truenas-pool`, `log-budget`, `memory` (< 10 % free). A firing notification marks the
check down, a resolved one marks it up (keyword filters on the request body). The
notification goes to the Discord integration **VWP BACKUP** only (`HC_CHANNELS` in
`alerts.nix`; the sync replaces a check's integrations with it, never "all": the
project also has the Raika Discord). Tested end to end on 2026-10-23: a failed unit
took the check down after ~6.5 minutes and back up 2 minutes after it was cleared. `healthchecks-sync` creates the checks through the API on every switch
(read-write key in 1Password `healthchecks-api-key`; the free plan allows 20 checks).

- **One check per rule, grouped per host:** if two machines trip the same rule, the
  check turns green when the first recovers although the second is still bad, until
  the 4-hourly repeat. Look at Grafana's alert list when a check flaps.
- **Watchdog:** a rule that always fires pings `homelab-watchdog` every minute. If the
  monitor, Grafana, Prometheus or the network is down, the pings stop and Healthchecks
  alerts after 5 + 5 minutes.
- **When Healthchecks.io is unreachable** Grafana retries and the notifications are
  late; nothing is lost on the monitor's side.
- **TrueNAS's own alerts** (SMART, pool, updates) go to `homelab-truenas` through a
  TrueNAS alert service of type Slack (Alerts → Alert Services, "Healthchecks
  homelab-truenas"), posting to the check's `/fail` URL. Every TrueNAS alert, including
  "cleared", marks it down: after dealing with it, mark the check up again by pinging
  it once (`curl https://hc-ping.com/<ping key>/homelab-truenas`, the ping key is in
  1Password `healthchecks-ping-key`).

## Adding something

- **A new NixOS server** is monitored by being a server (`type = "server"`): it gets
  the agent, and the monitor scrapes it once both are applied.
- **A new exporter on a server:** run it, open nothing yourself, and declare
  `homelab.monitoring.targets.<name> = { port = …; };` in its module; the firewall
  rule and the Prometheus job (named `<name>`) follow.
- **A new route** is probed automatically.

## Secrets (1Password, vault Homelab)

`grafana-admin` (`password`, `secret-key`), `kanidm-oauth2-grafana`,
`pve-monitoring-token` (`env`), `healthchecks-ping-key` (`env`, `HC_PING_KEY=…`),
`healthchecks-api-key` (`credential` read-write; the source fields `ping_key`,
`read_only`, `project_uuid` live here too), `healthchecks-readonly-key`,
`healthchecks-project` (`uuid`), `truenas-automation`. Units that read them start after
`opnix-secrets` (`modules/server/monitoring/secrets.nix`).

## Rebuilding the monitor

It applies through Lodestar like the other servers (4 GB is enough to evaluate the
flake). Starting over: clone template 9000 to VM 140 (2 vCPU, 4 GB, 16 GB root on
`local-lvm`, `cpu: host`, `onboot`), add a 64 GB `store-lvm` disk and format it
`mkfs.ext4 -L monitor-data`, place the opnix token (`/etc/opnix-token`), switch to
`#monitor`, reboot, clone `stable` into `~monitor/.flake`. History starts empty.
