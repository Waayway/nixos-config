//! Bare git mirror of the config repo: channel heads, behind counts, commit
//! subjects and the `unstable` -> `stable` promote push.
//!
//! Every git call goes through `tokio::process::Command` with the host's git
//! configuration disabled and prompts off. Commit hashes are validated with
//! `is_commit_hash` and channel names are checked before they reach git, and
//! refs are always passed fully qualified, so a caller string can never be
//! parsed as an option.

use std::ffi::OsStr;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use anyhow::{Context, bail};
use fleet_proto::is_commit_hash;
use tokio::process::Command;

use crate::config::ServerConfig;

/// Upper bound for network git operations (fetch, push).
const NETWORK_TIMEOUT: Duration = Duration::from_secs(120);

pub struct Mirror {
    path: PathBuf,
    repo_url: String,
    push_url: String,
    deploy_key: Option<PathBuf>,
}

struct Output {
    code: Option<i32>,
    stdout: String,
    stderr: String,
}

impl Output {
    fn ok(&self) -> bool {
        self.code == Some(0)
    }
}

fn valid_channel(channel: &str) -> bool {
    !channel.is_empty()
        && !channel.starts_with(['-', '.', '/'])
        && !channel.contains("..")
        && channel
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '/'))
}

impl Mirror {
    /// Creates `<state_dir>/mirror.git` when missing and does a first fetch. A failing first
    /// fetch is not fatal (the server may start offline); later `fetch` calls report errors.
    pub async fn open_or_init(cfg: &ServerConfig) -> anyhow::Result<Mirror> {
        let path = cfg.state_dir.join("mirror.git");
        let mirror = Mirror {
            path,
            repo_url: cfg.repo_url.clone(),
            push_url: cfg.push_url.clone(),
            deploy_key: cfg.deploy_key_file.clone(),
        };
        if !mirror.path.join("HEAD").exists() {
            std::fs::create_dir_all(&mirror.path)
                .with_context(|| format!("creating {}", mirror.path.display()))?;
            let out = mirror.git(["init", "--bare", "--quiet"]).await?;
            if !out.ok() {
                bail!("git init failed: {}", out.stderr.trim());
            }
        }
        if let Err(e) = mirror.fetch().await {
            eprintln!("fleet-server: initial mirror fetch failed: {e:#}");
        }
        Ok(mirror)
    }

    async fn git<I, S>(&self, args: I) -> anyhow::Result<Output>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let mut cmd = Command::new("git");
        cmd.arg("--git-dir")
            .arg(&self.path)
            .args(args)
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .stdin(Stdio::null())
            .kill_on_drop(true);
        if let Some(key) = &self.deploy_key {
            cmd.env(
                "GIT_SSH_COMMAND",
                format!(
                    "ssh -i {} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes",
                    key.display()
                ),
            );
        }
        let out = tokio::time::timeout(NETWORK_TIMEOUT, cmd.output())
            .await
            .context("git timed out")?
            .context("running git")?;
        Ok(Output {
            code: out.status.code(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        })
    }

    pub async fn fetch(&self) -> anyhow::Result<()> {
        let out = self
            .git([
                "fetch",
                "--quiet",
                "--prune",
                "--",
                &self.repo_url,
                "+refs/heads/*:refs/heads/*",
            ])
            .await?;
        if !out.ok() {
            bail!("git fetch failed: {}", out.stderr.trim());
        }
        Ok(())
    }

    /// Commit at the head of `channel`, if the branch exists in the mirror.
    pub async fn head(&self, channel: &str) -> Option<String> {
        if !valid_channel(channel) {
            return None;
        }
        let refname = format!("refs/heads/{channel}^{{commit}}");
        let out = self
            .git(["rev-parse", "--verify", "--quiet", &refname])
            .await
            .ok()?;
        let hash = out.stdout.trim();
        (out.ok() && is_commit_hash(hash)).then(|| hash.to_string())
    }

    /// First line of the commit message.
    pub async fn subject(&self, commit: &str) -> Option<String> {
        if !is_commit_hash(commit) {
            return None;
        }
        let out = self
            .git(["log", "-1", "--format=%s", commit, "--"])
            .await
            .ok()?;
        out.ok().then(|| out.stdout.trim().to_string())
    }

    async fn has_commit(&self, commit: &str) -> bool {
        is_commit_hash(commit)
            && self
                .git(["cat-file", "-e", &format!("{commit}^{{commit}}")])
                .await
                .is_ok_and(|o| o.ok())
    }

    /// `Ok(true)` when `ancestor` is an ancestor of (or equal to) `descendant`.
    /// Both must be full hashes or full ref names.
    async fn is_ancestor(&self, ancestor: &str, descendant: &str) -> anyhow::Result<bool> {
        let out = self
            .git(["merge-base", "--is-ancestor", ancestor, descendant])
            .await?;
        match out.code {
            Some(0) => Ok(true),
            Some(1) => Ok(false),
            _ => bail!("git merge-base failed: {}", out.stderr.trim()),
        }
    }

    /// Commits on `channel` that are not in `running` (a trailing `-dirty` is ignored).
    /// `None` when `running` is not a commit hash, is not in the mirror, or the channel is unknown.
    pub async fn behind_count(&self, running: &str, channel: &str) -> Option<u32> {
        let running = running.strip_suffix("-dirty").unwrap_or(running);
        if !is_commit_hash(running) || !valid_channel(channel) || !self.has_commit(running).await {
            return None;
        }
        let range = format!("{running}..refs/heads/{channel}");
        let out = self.git(["rev-list", "--count", &range, "--"]).await.ok()?;
        if !out.ok() {
            return None;
        }
        out.stdout.trim().parse().ok()
    }

    /// The `unstable` head when `stable` is a strict ancestor of it.
    pub async fn promote_candidate(&self) -> Option<String> {
        let unstable = self.head("unstable").await?;
        let stable = self.head("stable").await?;
        if stable == unstable {
            return None;
        }
        self.is_ancestor(&stable, &unstable)
            .await
            .ok()
            .filter(|&a| a)
            .map(|_| unstable)
    }

    /// Fast-forwards `stable` to `commit` (non-force push). `commit` must be on `unstable` and
    /// `stable` must be an ancestor of it.
    pub async fn promote(&self, commit: &str) -> anyhow::Result<()> {
        if !is_commit_hash(commit) {
            bail!("not a commit hash");
        }
        if !self.has_commit(commit).await {
            bail!("commit {commit} is not in the mirror");
        }
        if !self.is_ancestor(commit, "refs/heads/unstable").await? {
            bail!("commit {commit} is not on unstable");
        }
        if let Some(stable) = self.head("stable").await
            && !self.is_ancestor(&stable, commit).await?
        {
            bail!("stable ({stable}) is not an ancestor of {commit}");
        }
        let out = self
            .git([
                "push",
                "--quiet",
                "--",
                &self.push_url,
                &format!("{commit}:refs/heads/stable"),
            ])
            .await?;
        if !out.ok() {
            bail!("git push failed: {}", out.stderr.trim());
        }
        Ok(())
    }
}
