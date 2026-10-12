//! Host reachability and viewer identity, from the `tailscale` CLI.

use std::collections::HashMap;
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use anyhow::Context;
use serde::Deserialize;

use crate::config::OnlineSource;

const STATUS_TTL: Duration = Duration::from_secs(30);
const WHOIS_TTL: Duration = Duration::from_secs(60);
const CLI_TIMEOUT: Duration = Duration::from_secs(10);
/// `LoginName` Tailscale reports for tagged devices (they have no user).
const TAGGED_LOGIN: &str = "tagged-devices";

#[derive(Clone, Debug, PartialEq)]
pub struct PeerInfo {
    pub host: String,
    pub online: bool,
    /// Unix seconds; `None` when Tailscale has never seen the node.
    pub last_seen: Option<i64>,
    pub os: String,
    pub addr: Option<IpAddr>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Identity {
    pub login: Option<String>,
    pub tags: Vec<String>,
    /// Short host name of the node the request came from.
    pub node: String,
}

#[derive(Deserialize)]
struct RawStatus {
    #[serde(rename = "Self")]
    this: Option<RawPeer>,
    #[serde(rename = "Peer", default)]
    peer: Option<HashMap<String, RawPeer>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawPeer {
    #[serde(default)]
    host_name: String,
    #[serde(rename = "DNSName", default)]
    dns_name: String,
    #[serde(default)]
    online: bool,
    #[serde(default)]
    last_seen: Option<String>,
    #[serde(rename = "OS", default)]
    os: String,
    #[serde(rename = "TailscaleIPs", default)]
    tailscale_ips: Vec<IpAddr>,
}

/// Parses `tailscale status --json`, including this node. Key = lowercased HostName.
///
/// HostName is not unique in a tailnet. Collisions resolve deterministically:
/// Self wins, else online beats offline, then the later `last_seen`, then the
/// lexicographically smaller DNSName. A warning is logged for each collision.
pub fn parse_status(json: &str) -> anyhow::Result<HashMap<String, PeerInfo>> {
    let raw: RawStatus = serde_json::from_str(json).context("parsing tailscale status")?;
    let candidates = raw.this.into_iter().map(|p| (true, p)).chain(
        raw.peer
            .into_iter()
            .flat_map(|m| m.into_values())
            .map(|p| (false, p)),
    );
    let mut out: HashMap<String, (bool, String, PeerInfo)> = HashMap::new();
    for (is_self, p) in candidates {
        let host = p.host_name.to_lowercase();
        if host.is_empty() {
            continue;
        }
        let addr = p
            .tailscale_ips
            .iter()
            .find(|ip| ip.is_ipv4())
            .or_else(|| p.tailscale_ips.first())
            .copied();
        let info = PeerInfo {
            host: host.clone(),
            online: p.online,
            last_seen: p.last_seen.as_deref().and_then(parse_last_seen),
            os: p.os,
            addr,
        };
        let new = (is_self, p.dns_name, info);
        match out.remove(&host) {
            None => {
                out.insert(host, new);
            }
            Some(old) => {
                eprintln!(
                    "fleet-server: duplicate tailscale HostName {host:?}; picking one deterministically"
                );
                out.insert(host, if wins(&new, &old) { new } else { old });
            }
        }
    }
    Ok(out.into_iter().map(|(k, (_, _, info))| (k, info)).collect())
}

/// True if `a` should replace `b` for the same host name.
fn wins(a: &(bool, String, PeerInfo), b: &(bool, String, PeerInfo)) -> bool {
    // Self first, then online, then later last_seen (None is oldest), then smaller DNSName.
    let key = |x: &(bool, String, PeerInfo)| (x.0, x.2.online, x.2.last_seen);
    match key(a).cmp(&key(b)) {
        std::cmp::Ordering::Equal => a.1 < b.1,
        o => o.is_gt(),
    }
}

fn parse_last_seen(s: &str) -> Option<i64> {
    let t = chrono::DateTime::parse_from_rfc3339(s).ok()?.timestamp();
    // Go's zero time ("0001-01-01T00:00:00Z") means never seen.
    (t > 0).then_some(t)
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawWhois {
    node: RawNode,
    #[serde(default)]
    user_profile: Option<RawProfile>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawNode {
    #[serde(default)]
    name: String,
    #[serde(default)]
    computed_name: String,
    #[serde(default)]
    tags: Option<Vec<String>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawProfile {
    #[serde(default)]
    login_name: String,
}

/// Parses `tailscale whois --json <ip>`.
pub fn parse_whois(json: &str) -> anyhow::Result<Identity> {
    let raw: RawWhois = serde_json::from_str(json).context("parsing tailscale whois")?;
    let node = if raw.node.computed_name.is_empty() {
        raw.node
            .name
            .split('.')
            .next()
            .unwrap_or_default()
            .to_string()
    } else {
        raw.node.computed_name
    };
    let login = raw
        .user_profile
        .map(|u| u.login_name)
        .filter(|l| !l.is_empty() && l != TAGGED_LOGIN);
    Ok(Identity {
        login,
        tags: raw.node.tags.unwrap_or_default(),
        node,
    })
}

#[async_trait::async_trait]
pub trait OnlineProvider: Send + Sync {
    async fn peers(&self) -> HashMap<String, PeerInfo>;
    async fn whois(&self, ip: IpAddr) -> Option<Identity>;
}

/// Shells out to the `tailscale` binary; status cached 30 s, whois 60 s.
pub struct TailscaleCli {
    bin: PathBuf,
    status: Mutex<Option<(Instant, HashMap<String, PeerInfo>)>>,
    whois: Mutex<HashMap<IpAddr, (Instant, Identity)>>,
}

impl TailscaleCli {
    pub fn new(bin: PathBuf) -> Self {
        Self {
            bin,
            status: Mutex::new(None),
            whois: Mutex::new(HashMap::new()),
        }
    }

    async fn run(&self, args: &[&str]) -> anyhow::Result<String> {
        let mut cmd = tokio::process::Command::new(&self.bin);
        cmd.args(args).kill_on_drop(true);
        let out = tokio::time::timeout(CLI_TIMEOUT, cmd.output())
            .await
            .context("tailscale timed out")?
            .context("running tailscale")?;
        anyhow::ensure!(out.status.success(), "tailscale exited with {}", out.status);
        Ok(String::from_utf8(out.stdout)?)
    }
}

#[async_trait::async_trait]
impl OnlineProvider for TailscaleCli {
    async fn peers(&self) -> HashMap<String, PeerInfo> {
        let cached = self.status.lock().unwrap().clone();
        if let Some((at, map)) = &cached
            && at.elapsed() < STATUS_TTL
        {
            return map.clone();
        }
        let fresh = match self
            .run(&["status", "--json"])
            .await
            .and_then(|s| parse_status(&s))
        {
            Ok(map) => map,
            Err(_) => return cached.map(|(_, m)| m).unwrap_or_default(),
        };
        *self.status.lock().unwrap() = Some((Instant::now(), fresh.clone()));
        fresh
    }

    async fn whois(&self, ip: IpAddr) -> Option<Identity> {
        if let Some((at, id)) = self.whois.lock().unwrap().get(&ip)
            && at.elapsed() < WHOIS_TTL
        {
            return Some(id.clone());
        }
        let ip_s = ip.to_string();
        let id = self
            .run(&["whois", "--json", &ip_s])
            .await
            .and_then(|s| parse_whois(&s))
            .ok()?;
        let mut cache = self.whois.lock().unwrap();
        cache.retain(|_, (at, _)| at.elapsed() < WHOIS_TTL);
        cache.insert(ip, (Instant::now(), id.clone()));
        Some(id)
    }
}

/// A static address is an IP, or (tests/dev only) `ip:port` when the agent listens on a
/// non-default port; see `poller::agent_base`.
pub fn parse_static_addr(s: &str) -> Option<IpAddr> {
    s.parse::<IpAddr>()
        .ok()
        .or_else(|| s.parse::<std::net::SocketAddr>().ok().map(|a| a.ip()))
}

/// Dev/test source: every configured host is always online.
pub struct StaticOnline {
    peers: HashMap<String, PeerInfo>,
}

impl StaticOnline {
    pub fn new(addresses: &HashMap<String, String>) -> anyhow::Result<Self> {
        let mut peers = HashMap::new();
        for (name, addr) in addresses {
            let host = name.to_lowercase();
            let addr = parse_static_addr(addr)
                .with_context(|| format!("static address for {name}: {addr:?}"))?;
            peers.insert(
                host.clone(),
                PeerInfo {
                    host,
                    online: true,
                    last_seen: None,
                    os: String::new(),
                    addr: Some(addr),
                },
            );
        }
        Ok(Self { peers })
    }
}

#[async_trait::async_trait]
impl OnlineProvider for StaticOnline {
    async fn peers(&self) -> HashMap<String, PeerInfo> {
        self.peers.clone()
    }
    async fn whois(&self, _ip: IpAddr) -> Option<Identity> {
        None
    }
}

/// Builds the provider selected by the config.
pub fn provider_from_config(
    source: &OnlineSource,
    tailscale_bin: &std::path::Path,
) -> anyhow::Result<std::sync::Arc<dyn OnlineProvider>> {
    Ok(match source {
        OnlineSource::Tailscale => {
            std::sync::Arc::new(TailscaleCli::new(tailscale_bin.to_path_buf()))
        }
        OnlineSource::Static { addresses } => std::sync::Arc::new(StaticOnline::new(addresses)?),
    })
}
