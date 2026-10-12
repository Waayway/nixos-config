//! Builds the `GET /status` document.

use std::process::Command;

use fleet_proto::{AgentStatus, CheckoutStatus};

use crate::apply::latest_record;
use crate::config::AgentConfig;
use crate::git::Git;

fn revision_argv(cfg: &AgentConfig) -> Option<Vec<String>> {
    if let Some(c) = &cfg.revision_command {
        return Some(c.clone());
    }
    let prog = match cfg.os.as_str() {
        "linux" => "/run/current-system/sw/bin/nixos-version",
        "darwin" => "/run/current-system/sw/bin/darwin-version",
        _ => return None,
    };
    Some(vec![prog.to_string()])
}

/// The running system's configuration revision, or "unknown".
pub fn running_revision(cfg: &AgentConfig) -> String {
    let Some(argv) = revision_argv(cfg) else {
        return "unknown".into();
    };
    let Some((prog, args)) = argv.split_first() else {
        return "unknown".into();
    };
    Command::new(prog)
        .args(args)
        .arg("--configuration-revision")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".into())
}

pub fn last_fetch_at(cfg: &AgentConfig) -> Option<i64> {
    std::fs::read_to_string(cfg.state_dir.join("last_fetch"))
        .ok()?
        .trim()
        .parse()
        .ok()
}

pub fn collect(cfg: &AgentConfig, git: &Git) -> AgentStatus {
    AgentStatus {
        host: cfg.host.clone(),
        os: cfg.os.clone(),
        agent_version: env!("CARGO_PKG_VERSION").to_string(),
        running: running_revision(cfg),
        checkout: CheckoutStatus {
            branch: git.current_branch(),
            head: git.head(),
            dirty: git.is_dirty(),
            untracked: git.untracked_count(),
            ahead: git.ahead_of(&format!("refs/remotes/origin/{}", cfg.channel)),
            last_fetch_at: last_fetch_at(cfg),
        },
        apply: latest_record(cfg),
    }
}
