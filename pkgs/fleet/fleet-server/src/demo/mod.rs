//! Demo mode: the real server, poller, database, git mirror and dashboard against a
//! simulated fleet (a throwaway git repo and in-process simulated agents). All demo
//! timings are divided by `speed`.

mod agents;
mod online;
mod repo;

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Context;
use tempfile::TempDir;
use tokio::task::JoinHandle;

use crate::config::{AccessConfig, FleetHost, OnlineSource, ServerConfig};
use crate::server::{self, ServerHandle};
use crate::state::AppState;

use agents::{HostSetup, Script, SimAgent};
use online::{DemoOnline, DemoPeer};
use repo::{DemoRepo, STABLE_AT};

/// Seconds between new commits on `unstable`.
const COMMIT_EVERY_SECS: f64 = 180.0;
/// Seconds apollo stays offline.
const APOLLO_OFFLINE_SECS: f64 = 120.0;
const POLL_SECS: f64 = 5.0;
const MIRROR_FETCH_SECS: f64 = 30.0;
const DEMO_USER: &str = "demo";

pub(crate) fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// One row of the demo fleet.
struct DemoHost {
    name: &'static str,
    system: &'static str,
    channel: &'static str,
    /// Commits behind the channel head at start.
    behind: usize,
    script: Script,
    /// Offline for this many seconds (unscaled) after start.
    offline_for: Option<f64>,
    /// Online in Tailscale but nothing answers on the agent port.
    unreachable: bool,
}

const fn host(
    name: &'static str,
    system: &'static str,
    channel: &'static str,
    behind: usize,
) -> DemoHost {
    DemoHost {
        name,
        system,
        channel,
        behind,
        script: Script::Succeed,
        offline_for: None,
        unreachable: false,
    }
}

const FLEET: [DemoHost; 7] = [
    DemoHost {
        script: Script::Dirty,
        ..host("atlas", "aarch64-darwin", "unstable", 3)
    },
    DemoHost {
        offline_for: Some(APOLLO_OFFLINE_SECS),
        ..host("apollo", "aarch64-darwin", "unstable", 5)
    },
    host("hermes", "x86_64-linux", "unstable", 2),
    DemoHost {
        unreachable: true,
        ..host("hephaestus", "x86_64-linux", "unstable", 1)
    },
    host("nixos-manager", "x86_64-linux", "stable", 0),
    host("vpn", "x86_64-linux", "stable", 1),
    DemoHost {
        script: Script::FailFirst,
        ..host("media", "x86_64-linux", "stable", 1)
    },
];

/// Aborts the tasks when dropped.
struct Tasks(Vec<JoinHandle<()>>);

impl Drop for Tasks {
    fn drop(&mut self) {
        for t in &self.0 {
            t.abort();
        }
    }
}

/// A running demo. Dropping it stops the server, the simulated agents and the commit
/// ticker, then deletes the temp dir.
pub struct DemoHandle {
    pub addr: SocketAddr,
    pub state: AppState,
    server: ServerHandle,
    tasks: Tasks,
    _tmp: TempDir,
}

impl DemoHandle {
    /// Serves until the server fails.
    pub async fn wait(self) -> anyhow::Result<()> {
        let DemoHandle {
            server,
            tasks,
            _tmp,
            ..
        } = self;
        let result = server.wait().await;
        drop(tasks);
        result
    }
}

fn scaled(secs: f64, speed: f64) -> Duration {
    Duration::from_secs_f64(secs / speed)
}

fn scaled_secs(secs: f64, speed: f64) -> u64 {
    ((secs / speed).round() as u64).max(1)
}

/// A local port with nothing listening on it.
fn closed_port() -> anyhow::Result<u16> {
    let l = std::net::TcpListener::bind("127.0.0.1:0").context("finding a free port")?;
    Ok(l.local_addr()?.port())
}

/// Starts the demo; returns once the dashboard is listening on `listen`.
pub async fn start(listen: SocketAddr, speed: f64) -> anyhow::Result<DemoHandle> {
    anyhow::ensure!(
        speed.is_finite() && speed > 0.0,
        "speed must be a positive number"
    );
    if !listen.ip().is_loopback() {
        eprintln!(
            "fleet-server: warning: demo mode has no access control, and {listen} is not a loopback address"
        );
    }
    let tmp = tempfile::Builder::new()
        .prefix("fleet-demo-")
        .tempdir()
        .context("creating the demo temp dir")?;
    let (mut repo, commits) = DemoRepo::create(tmp.path()).await?;

    let mut tasks = Vec::new();
    let mut hosts = Vec::new();
    let mut peers = Vec::new();
    let mut addresses = HashMap::new();
    let start = now();
    for (i, h) in FLEET.iter().enumerate() {
        let os = if h.system.ends_with("darwin") {
            "darwin"
        } else {
            "linux"
        };
        let head = if h.channel == "stable" {
            STABLE_AT
        } else {
            commits.len()
        };
        let running = commits[head - 1 - h.behind].clone();
        let addr = if h.unreachable {
            SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), closed_port()?)
        } else {
            let setup = HostSetup {
                name: h.name.into(),
                os: os.into(),
                channel: h.channel.into(),
                user: DEMO_USER.into(),
                running,
                script: h.script,
                generation: 40 + 7 * i as u64,
                activated_at: start - (2 + i as i64) * 3600,
            };
            let (addr, task) = agents::serve(Arc::new(SimAgent::new(setup, speed))).await?;
            tasks.push(task);
            addr
        };
        addresses.insert(h.name.to_string(), addr.to_string());
        peers.push(DemoPeer {
            host: h.name.into(),
            os: if os == "darwin" { "macOS" } else { "linux" }.into(),
            addr: addr.ip(),
            offline_for: h.offline_for.map(|s| scaled(s, speed)),
        });
        hosts.push(FleetHost {
            name: h.name.into(),
            system: h.system.into(),
            user: DEMO_USER.into(),
            channel: h.channel.into(),
            os: os.into(),
        });
    }

    let hosts_file = tmp.path().join("hosts.json");
    std::fs::write(&hosts_file, serde_json::to_vec_pretty(&hosts)?)
        .with_context(|| format!("writing {}", hosts_file.display()))?;
    let repo_url = repo
        .bare
        .to_str()
        .context("temp dir path is not UTF-8")?
        .to_string();
    let cfg = ServerConfig {
        listen,
        agent_port: 7461,
        hosts_file,
        repo_url: repo_url.clone(),
        push_url: repo_url,
        deploy_key_file: None,
        state_dir: tmp.path().join("state"),
        access: AccessConfig::Disabled,
        // Agent addresses with their ports; reachability itself comes from `DemoOnline`.
        online: OnlineSource::Static { addresses },
        mirror_fetch_secs: scaled_secs(MIRROR_FETCH_SECS, speed),
        poll_secs: scaled_secs(POLL_SECS, speed),
        tailscale_bin: "tailscale".into(),
    };
    let server = server::start(cfg, hosts, Arc::new(DemoOnline::new(peers)), true).await?;

    let every = scaled(COMMIT_EVERY_SECS, speed);
    tasks.push(tokio::spawn(async move {
        let mut tick = tokio::time::interval_at(tokio::time::Instant::now() + every, every);
        loop {
            tick.tick().await;
            match repo.land_commit().await {
                Ok(c) => eprintln!("fleet-server: demo: new commit {c} on unstable"),
                Err(e) => eprintln!("fleet-server: demo: new commit: {e:#}"),
            }
        }
    }));

    Ok(DemoHandle {
        addr: server.addr,
        state: server.state.clone(),
        server,
        tasks: Tasks(tasks),
        _tmp: tmp,
    })
}
