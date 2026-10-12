//! Server configuration (JSON file) and the fleet host list (`hosts.json`).

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};

use anyhow::Context;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum AccessConfig {
    Tailscale {
        #[serde(default)]
        allowed_users: Vec<String>,
        #[serde(default)]
        allowed_tags: Vec<String>,
    },
    Disabled,
}

/// Where host reachability comes from. `Static` is for tests/dev: always online.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum OnlineSource {
    Tailscale,
    /// Host name -> IP. An address may carry a port (`127.0.0.1:54321`, tests/dev only)
    /// to reach an agent that is not on `agent_port`.
    Static {
        addresses: HashMap<String, String>,
    },
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct ServerConfig {
    pub listen: SocketAddr,
    pub agent_port: u16,
    pub hosts_file: PathBuf,
    pub repo_url: String,
    pub push_url: String,
    #[serde(default)]
    pub deploy_key_file: Option<PathBuf>,
    pub state_dir: PathBuf,
    pub access: AccessConfig,
    pub online: OnlineSource,
    #[serde(default = "default_mirror_fetch_secs")]
    pub mirror_fetch_secs: u64,
    #[serde(default = "default_poll_secs")]
    pub poll_secs: u64,
    #[serde(default = "default_tailscale_bin")]
    pub tailscale_bin: PathBuf,
}

fn default_mirror_fetch_secs() -> u64 {
    300
}
fn default_poll_secs() -> u64 {
    60
}
fn default_tailscale_bin() -> PathBuf {
    PathBuf::from("tailscale")
}

impl ServerConfig {
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading config {}", path.display()))?;
        serde_json::from_str(&text).with_context(|| format!("parsing config {}", path.display()))
    }
}

/// True for Tailscale addresses: `100.64.0.0/10` and `fd7a:115c:a1e0::/48`.
pub fn is_tailscale_ip(ip: IpAddr) -> bool {
    match ip.to_canonical() {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            o[0] == 100 && (o[1] & 0xc0) == 64
        }
        IpAddr::V6(v6) => {
            let s = v6.segments();
            s[0] == 0xfd7a && s[1] == 0x115c && s[2] == 0xa1e0
        }
    }
}

impl ServerConfig {
    /// With Tailscale access control the dashboard must listen only on a Tailscale address:
    /// on any other address `whois` can't vouch for the peer.
    pub fn check_listen(&self) -> anyhow::Result<()> {
        if matches!(self.access, AccessConfig::Tailscale { .. })
            && !is_tailscale_ip(self.listen.ip())
        {
            anyhow::bail!(
                "listen address {} is not a Tailscale address (100.64.0.0/10 or fd7a:115c:a1e0::/48); \
                 with Tailscale access control the dashboard must listen only on the tailnet",
                self.listen
            );
        }
        Ok(())
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct FleetHost {
    pub name: String,
    pub system: String,
    pub user: String,
    pub channel: String,
    pub os: String,
}

pub fn load_hosts(path: &Path) -> anyhow::Result<Vec<FleetHost>> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading hosts file {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parsing hosts file {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_defaults_and_tags() {
        let c: ServerConfig = serde_json::from_str(
            r#"{"listen":"127.0.0.1:8080","agent_port":7461,"hosts_file":"/h.json",
            "repo_url":"u","push_url":"p","state_dir":"/s",
            "access":{"kind":"tailscale","allowed_users":["a@github"],"allowed_tags":["tag:fleet"]},
            "online":{"kind":"static","addresses":{"h":"127.0.0.1"}}}"#,
        )
        .unwrap();
        assert_eq!((c.mirror_fetch_secs, c.poll_secs), (300, 60));
        assert_eq!(c.tailscale_bin, PathBuf::from("tailscale"));
        assert_eq!(c.deploy_key_file, None);
        assert!(matches!(c.access, AccessConfig::Tailscale { .. }));
        let d: AccessConfig = serde_json::from_str(r#"{"kind":"disabled"}"#).unwrap();
        assert_eq!(d, AccessConfig::Disabled);
    }

    #[test]
    fn tailscale_ips() {
        for ip in [
            "100.64.0.1",
            "100.127.255.254",
            "fd7a:115c:a1e0::1",
            "::ffff:100.100.1.1",
        ] {
            assert!(is_tailscale_ip(ip.parse().unwrap()), "{ip}");
        }
        for ip in [
            "100.63.255.255",
            "100.128.0.1",
            "127.0.0.1",
            "0.0.0.0",
            "::",
            "fd7a:115c:a1e1::1",
        ] {
            assert!(!is_tailscale_ip(ip.parse().unwrap()), "{ip}");
        }
    }

    #[test]
    fn listen_must_be_tailscale_with_tailscale_access() {
        let mut c: ServerConfig = serde_json::from_str(
            r#"{"listen":"0.0.0.0:8080","agent_port":7461,"hosts_file":"/h.json",
            "repo_url":"u","push_url":"p","state_dir":"/s",
            "access":{"kind":"tailscale"},"online":{"kind":"tailscale"}}"#,
        )
        .unwrap();
        let err = c.check_listen().unwrap_err().to_string();
        assert!(err.contains("not a Tailscale address"), "{err}");
        c.listen = "100.100.1.2:8080".parse().unwrap();
        c.check_listen().unwrap();
        c.listen = "127.0.0.1:8080".parse().unwrap();
        c.access = AccessConfig::Disabled;
        c.check_listen().unwrap();
    }

    #[test]
    fn hosts_load() {
        let dir = std::env::temp_dir().join(format!("fleet-hosts-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("hosts.json");
        std::fs::write(
            &p,
            r#"[{"name":"a","system":"x86_64-linux","user":"u","channel":"main","os":"nixos"}]"#,
        )
        .unwrap();
        let h = load_hosts(&p).unwrap();
        assert_eq!(h[0].name, "a");
        std::fs::remove_dir_all(&dir).ok();
    }
}
