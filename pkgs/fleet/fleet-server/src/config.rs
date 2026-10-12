//! Server configuration (JSON file) and the fleet host list (`hosts.json`).

use std::collections::HashMap;
use std::net::SocketAddr;
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
    Static { addresses: HashMap<String, String> },
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
