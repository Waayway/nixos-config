#![allow(dead_code)]
use std::path::{Path, PathBuf};
use std::process::Command;

use fleet_agent::config::{AgentConfig, Launcher};
use tempfile::TempDir;

pub struct Fixture {
    pub _tmp: TempDir,
    pub remote: PathBuf,
    pub clone: PathBuf,
    pub cfg: AgentConfig,
}

/// Runs git with a fixed identity and no global/system config.
pub fn git(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_SYSTEM", "/dev/null")
        .env("GIT_AUTHOR_NAME", "t")
        .env("GIT_AUTHOR_EMAIL", "t@example.com")
        .env("GIT_COMMITTER_NAME", "t")
        .env("GIT_COMMITTER_EMAIL", "t@example.com")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?} failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

pub fn commit_file(dir: &Path, name: &str, content: &str) -> String {
    std::fs::write(dir.join(name), content).unwrap();
    git(dir, &["add", name]);
    git(dir, &["commit", "-q", "-m", name]);
    git(dir, &["rev-parse", "HEAD"])
}

/// Bare remote with `unstable` and `stable`, plus a clone on `unstable`.
pub fn fixture() -> Fixture {
    let tmp = TempDir::new().unwrap();
    let remote = tmp.path().join("remote.git");
    let seed = tmp.path().join("seed");
    let clone = tmp.path().join("clone");
    std::fs::create_dir_all(&remote).unwrap();
    std::fs::create_dir_all(&seed).unwrap();
    git(&remote, &["init", "-q", "--bare", "-b", "unstable"]);
    git(&seed, &["init", "-q", "-b", "unstable"]);
    commit_file(&seed, "a.txt", "a");
    git(&seed, &["branch", "stable"]);
    git(
        &seed,
        &["push", "-q", remote.to_str().unwrap(), "unstable", "stable"],
    );
    git(
        tmp.path(),
        &[
            "clone",
            "-q",
            "-b",
            "unstable",
            remote.to_str().unwrap(),
            clone.to_str().unwrap(),
        ],
    );
    let cfg = AgentConfig {
        host: "h".into(),
        user: std::env::var("USER").unwrap_or_else(|_| "root".into()),
        channel: "unstable".into(),
        flake_path: clone.clone(),
        repo_url: remote.to_string_lossy().into_owned(),
        port: 7461,
        manager_host: "m".into(),
        listen: None,
        state_dir: tmp.path().join("state"),
        rebuild_command: None,
        launcher: Launcher::Inline,
        os: "linux".into(),
    };
    Fixture {
        _tmp: tmp,
        remote,
        clone,
        cfg,
    }
}

/// Adds a commit to the remote's `unstable` via a scratch clone; returns its hash.
pub fn push_remote_commit(f: &Fixture, name: &str) -> String {
    let w = f._tmp.path().join(format!("w-{name}"));
    git(
        f._tmp.path(),
        &[
            "clone",
            "-q",
            "-b",
            "unstable",
            f.remote.to_str().unwrap(),
            w.to_str().unwrap(),
        ],
    );
    let c = commit_file(&w, name, name);
    git(&w, &["push", "-q", "origin", "unstable"]);
    c
}
