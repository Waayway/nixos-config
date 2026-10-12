//! The demo's stand-in for Tailscale: every demo host is a peer, and a host scripted to be
//! off comes online after a while.

use std::collections::HashMap;
use std::net::IpAddr;
use std::time::{Duration, Instant};

use super::now;
use crate::tailscale::{Identity, OnlineProvider, PeerInfo};

/// How long before the demo started an offline demo host was last seen.
const OFFLINE_LAST_SEEN_SECS: i64 = 3 * 3600;

pub struct DemoPeer {
    pub host: String,
    /// Tailscale's OS name (`macOS`, `linux`).
    pub os: String,
    pub addr: IpAddr,
    /// Off for this long after the demo starts (already scaled by speed).
    pub offline_for: Option<Duration>,
}

pub struct DemoOnline {
    started: Instant,
    started_unix: i64,
    peers: Vec<DemoPeer>,
}

impl DemoOnline {
    pub fn new(peers: Vec<DemoPeer>) -> Self {
        Self {
            started: Instant::now(),
            started_unix: now(),
            peers,
        }
    }
}

#[async_trait::async_trait]
impl OnlineProvider for DemoOnline {
    async fn peers(&self) -> HashMap<String, PeerInfo> {
        let t = now();
        let elapsed = self.started.elapsed();
        self.peers
            .iter()
            .map(|p| {
                let online = p.offline_for.is_none_or(|d| elapsed >= d);
                let last_seen = if online {
                    t
                } else {
                    self.started_unix - OFFLINE_LAST_SEEN_SECS
                };
                let key = p.host.to_lowercase();
                let info = PeerInfo {
                    host: key.clone(),
                    online,
                    last_seen: Some(last_seen),
                    os: p.os.clone(),
                    addr: Some(p.addr),
                };
                (key, info)
            })
            .collect()
    }

    async fn whois(&self, _ip: IpAddr) -> Option<Identity> {
        None
    }
}
