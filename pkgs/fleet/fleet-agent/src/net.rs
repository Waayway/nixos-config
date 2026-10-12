//! Tailscale address discovery and the manager source check.

use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const CACHE_TTL: Duration = Duration::from_secs(60);

/// True for addresses in 100.64.0.0/10 or fd7a:115c:a1e0::/48.
pub fn is_tailscale(ip: IpAddr) -> bool {
    match ip.to_canonical() {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            o[0] == 100 && (o[1] & 0xC0) == 0x40
        }
        IpAddr::V6(v6) => v6.segments()[..3] == [0xfd7a, 0x115c, 0xa1e0],
    }
}

/// Tailscale addresses of the local interfaces.
pub fn tailscale_addrs() -> Vec<IpAddr> {
    if_addrs::get_if_addrs()
        .map(|ifs| {
            ifs.into_iter()
                .map(|i| i.ip())
                .filter(|ip| is_tailscale(*ip))
                .collect()
        })
        .unwrap_or_default()
}

/// Allows only the addresses the manager host currently resolves to.
pub struct SourceGuard {
    host: String,
    cache: Mutex<Option<(Instant, Vec<IpAddr>)>>,
}

impl SourceGuard {
    pub fn new(host: String) -> Self {
        SourceGuard {
            host,
            cache: Mutex::new(None),
        }
    }

    pub async fn allows(&self, ip: IpAddr) -> bool {
        let ip = ip.to_canonical();
        let cached = {
            let c = self.cache.lock().unwrap();
            c.as_ref()
                .map(|(at, ips)| (at.elapsed() < CACHE_TTL, ips.clone()))
        };
        let ips = match cached {
            Some((true, ips)) => ips,
            stale => match tokio::net::lookup_host((self.host.as_str(), 0)).await {
                Ok(addrs) => {
                    let ips: Vec<IpAddr> = addrs.map(|a| a.ip().to_canonical()).collect();
                    *self.cache.lock().unwrap() = Some((Instant::now(), ips.clone()));
                    ips
                }
                // Keep using the last answer if DNS is briefly unavailable.
                Err(_) => stale.map(|(_, ips)| ips).unwrap_or_default(),
            },
        };
        ips.contains(&ip)
    }
}
