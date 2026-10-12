//! The demo's throwaway config repo: a bare `fleet.git` (the server's "GitHub") and a work
//! clone that commits to `unstable`.

use std::path::{Path, PathBuf};
use std::process::Stdio;

use anyhow::{Context, bail};
use tokio::process::Command;

use super::now;

/// Subjects of the seeded `unstable` history, oldest first.
const SEED_SUBJECTS: [&str; 12] = [
    "feat(darwin): Finder list view in Recents, no .DS_Store on shares/USB, drop Ice",
    "feat(darwin): PostgreSQL 18 + pgvector service, lxml/xmlsec build libs",
    "feat(darwin): openssl@3 on PKG_CONFIG_PATH for xmlsec, wkhtmltopdf",
    "fix(ghostty): no auto secure input on macOS (blocked AeroSpace bindings)",
    "fix(vscodium): turn off the self-updater on macOS",
    "fix: drop plain neovim so nvim is the nixvim build",
    "fix(vscodium): run the settings.json edit as the user",
    "fix: nixos-manager and hephaestus evaluate again",
    "feat(fleet): channel, fleet host list and configurationRevision",
    "feat(fleet): cargo workspace, fleet-proto types, dev shell and crane packaging",
    "feat(fleet-agent): HTTP API, tailscale discovery, source check, activations",
    "feat(fleet): agent service modules and activation audit hook",
];

/// `stable` starts at this seeded commit (1-based).
pub const STABLE_AT: usize = 8;

/// Subjects for the commits that keep landing on `unstable`, used in turn.
const NEW_SUBJECTS: [&str; 8] = [
    "fix(zsh): skip cd=z alias in Claude Code shells",
    "feat(hermes): bump immich to the latest release",
    "fix(media): jellyfin hardware transcoding on the iGPU",
    "chore: nix flake update",
    "feat(vpn): wireguard peer for the travel router",
    "fix(atlas): aerospace gaps on the external display",
    "feat(nixos-manager): nightly restic backup of /var/lib",
    "fix(apollo): battery-friendly tailscale settings",
];

async fn git(dir: &Path, args: &[&str], date: Option<i64>) -> anyhow::Result<String> {
    let mut cmd = Command::new("git");
    cmd.current_dir(dir)
        .args([
            "-c",
            "user.name=fleet-demo",
            "-c",
            "user.email=demo@fleet.invalid",
        ])
        .args(args)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null())
        .kill_on_drop(true);
    if let Some(t) = date {
        let d = format!("@{t} +0000");
        cmd.env("GIT_AUTHOR_DATE", &d).env("GIT_COMMITTER_DATE", &d);
    }
    let out = cmd
        .output()
        .await
        .with_context(|| format!("running git {args:?}"))?;
    if !out.status.success() {
        bail!(
            "git {args:?} failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub struct DemoRepo {
    /// The bare repo: the server's `repo_url` and `push_url`.
    pub bare: PathBuf,
    work: PathBuf,
    next_subject: usize,
}

impl DemoRepo {
    /// Creates the repos under `dir` and seeds `unstable` (12 commits, a few hours apart)
    /// and `stable` (at the 8th). Returns the repo and the seeded commits, oldest first.
    pub async fn create(dir: &Path) -> anyhow::Result<(DemoRepo, Vec<String>)> {
        let bare = dir.join("fleet.git");
        let work = dir.join("work");
        std::fs::create_dir_all(&work).with_context(|| format!("creating {}", work.display()))?;
        let bare_s = bare.to_str().context("temp dir path is not UTF-8")?;
        git(
            dir,
            &["init", "--quiet", "--bare", "-b", "unstable", bare_s],
            None,
        )
        .await?;
        git(&work, &["init", "--quiet", "-b", "unstable"], None).await?;
        git(&work, &["remote", "add", "origin", bare_s], None).await?;
        let repo = DemoRepo {
            bare,
            work,
            next_subject: 0,
        };
        let start = now() - 3 * 24 * 3600;
        let mut commits = Vec::with_capacity(SEED_SUBJECTS.len());
        for (i, subject) in SEED_SUBJECTS.iter().enumerate() {
            commits.push(repo.commit_at(subject, start + i as i64 * 5 * 3600).await?);
        }
        git(
            &repo.work,
            &["push", "--quiet", "origin", "HEAD:refs/heads/unstable"],
            None,
        )
        .await?;
        let stable = format!("{}:refs/heads/stable", commits[STABLE_AT - 1]);
        git(&repo.work, &["push", "--quiet", "origin", &stable], None).await?;
        Ok((repo, commits))
    }

    async fn commit_at(&self, subject: &str, time: i64) -> anyhow::Result<String> {
        git(
            &self.work,
            &["commit", "--quiet", "--allow-empty", "-m", subject],
            Some(time),
        )
        .await?;
        git(&self.work, &["rev-parse", "HEAD"], None).await
    }

    /// Commits the next realistic subject to `unstable` and pushes it.
    pub async fn land_commit(&mut self) -> anyhow::Result<String> {
        let subject = NEW_SUBJECTS[self.next_subject % NEW_SUBJECTS.len()];
        self.next_subject += 1;
        let commit = self.commit_at(subject, now()).await?;
        git(
            &self.work,
            &["push", "--quiet", "origin", "HEAD:refs/heads/unstable"],
            None,
        )
        .await?;
        Ok(commit)
    }
}
