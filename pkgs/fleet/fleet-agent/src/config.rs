use std::net::SocketAddr;
use std::path::{Path, PathBuf};

use anyhow::Context;
use serde::{Deserialize, Serialize};

/// How the apply wrapper detaches the rebuild from the daemon.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Launcher {
    SystemdRun,
    Detach,
    Inline,
}

/// Agent configuration, a JSON file passed as `--config <path>`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentConfig {
    pub host: String,
    pub user: String,
    pub channel: String,
    pub flake_path: PathBuf,
    pub repo_url: String,
    #[serde(default = "default_port")]
    pub port: u16,
    pub manager_host: String,
    #[serde(default)]
    pub listen: Option<SocketAddr>,
    #[serde(default = "default_state_dir")]
    pub state_dir: PathBuf,
    #[serde(default)]
    pub rebuild_command: Option<Vec<String>>,
    /// Command whose output (with `--configuration-revision` appended) is the
    /// running revision; defaults to the system's `nixos-version`/`darwin-version`.
    #[serde(default)]
    pub revision_command: Option<Vec<String>>,
    pub launcher: Launcher,
    /// Binary the launcher starts for an apply; defaults to the current executable.
    #[serde(default)]
    pub agent_exe: Option<PathBuf>,
    /// "linux" or "darwin"
    pub os: String,
}

fn default_port() -> u16 {
    7461
}

fn default_state_dir() -> PathBuf {
    PathBuf::from("/var/lib/fleet-agent")
}

pub fn load(path: &Path) -> anyhow::Result<AgentConfig> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("reading config {}", path.display()))?;
    serde_json::from_str(&raw).with_context(|| format!("parsing config {}", path.display()))
}
