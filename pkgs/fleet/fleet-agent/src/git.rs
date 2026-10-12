use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Output};

use anyhow::{Context, bail};
#[cfg(not(target_os = "macos"))]
use nix::unistd::initgroups;
use nix::unistd::{Gid, Uid, User, setgid, setuid};

use crate::config::AgentConfig;

/// Makes `cmd` run as `user` instead of root, with the user's own groups.
///
/// std applies `.uid()/.gid()` before `pre_exec` hooks, and root's supplementary
/// groups (wheel etc.) survive a plain uid/gid switch. So the whole drop happens
/// in one `pre_exec` hook, in the only safe order: supplementary groups first
/// (needs root), then gid, then uid (after which no further change is possible).
pub fn drop_privileges(cmd: &mut Command, user: &str, uid: u32, gid: u32, home: &std::path::Path) {
    let cuser = std::ffi::CString::new(user).expect("user name contains NUL");
    let (uid, gid) = (Uid::from_raw(uid), Gid::from_raw(gid));
    // SAFETY: the hook only calls async-signal-safe libc wrappers (initgroups,
    // setgroups, setgid, setuid) and does not allocate.
    unsafe {
        cmd.pre_exec(move || {
            // SAFETY: cuser is a valid NUL-terminated string; initgroups is
            // async-signal-safe enough for the post-fork, pre-exec window.
            if libc::initgroups(cuser.as_ptr(), gid.as_raw() as _) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            setgid(gid)?;
            setuid(uid)?;
            Ok(())
        });
    }
    cmd.env("HOME", home).env("USER", user).env("LOGNAME", user);
}

/// Runs git against the user's flake checkout, as that user.
pub struct Git {
    flake_path: PathBuf,
    user: String,
    /// (uid, gid, home); set only when running as root for a non-root user.
    run_as: Option<(u32, u32, PathBuf)>,
}

impl Git {
    pub fn new(cfg: &AgentConfig) -> anyhow::Result<Git> {
        let run_as = if Uid::effective().is_root() && cfg.user != "root" {
            let u = User::from_name(&cfg.user)
                .with_context(|| format!("looking up user {}", cfg.user))?
                .with_context(|| format!("no such user: {}", cfg.user))?;
            Some((u.uid.as_raw(), u.gid.as_raw(), u.dir))
        } else {
            None
        };
        Ok(Git {
            flake_path: cfg.flake_path.clone(),
            user: cfg.user.clone(),
            run_as,
        })
    }

    /// Runs `git -C <flake_path> <args>`. Non-zero exit is not an error here.
    pub fn run(&self, args: &[&str]) -> anyhow::Result<Output> {
        let mut cmd = Command::new("git");
        cmd.arg("-C")
            .arg(&self.flake_path)
            .args(args)
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("LC_ALL", "C");
        if let Some((uid, gid, home)) = &self.run_as {
            drop_privileges(&mut cmd, &self.user, *uid, *gid, home);
        }
        cmd.output()
            .with_context(|| format!("running git {}", args.join(" ")))
    }

    fn succeeds(&self, args: &[&str]) -> bool {
        self.run(args).map(|o| o.status.success()).unwrap_or(false)
    }

    fn stdout(&self, args: &[&str]) -> Option<String> {
        let o = self.run(args).ok()?;
        if !o.status.success() {
            return None;
        }
        Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
    }

    pub fn fetch(&self, repo_url: &str) -> anyhow::Result<()> {
        let out = self.run(&[
            "fetch",
            "--quiet",
            repo_url,
            "+refs/heads/*:refs/remotes/origin/*",
        ])?;
        if !out.status.success() {
            bail!(
                "git fetch failed: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            );
        }
        Ok(())
    }

    /// None on detached HEAD.
    pub fn current_branch(&self) -> Option<String> {
        self.stdout(&["symbolic-ref", "--quiet", "--short", "HEAD"])
            .filter(|b| !b.is_empty())
    }

    pub fn head(&self) -> Option<String> {
        self.stdout(&["rev-parse", "HEAD"])
            .filter(|h| !h.is_empty())
    }

    /// Tracked changes only; untracked files do not count.
    pub fn is_dirty(&self) -> bool {
        !self.succeeds(&["diff", "--quiet", "HEAD"])
    }

    pub fn untracked_count(&self) -> u32 {
        self.stdout(&["ls-files", "--others", "--exclude-standard"])
            .map(|s| s.lines().filter(|l| !l.is_empty()).count() as u32)
            .unwrap_or(0)
    }

    pub fn commit_exists(&self, c: &str) -> bool {
        self.succeeds(&["cat-file", "-e", &format!("{c}^{{commit}}")])
    }

    pub fn is_ancestor(&self, a: &str, b: &str) -> bool {
        self.succeeds(&["merge-base", "--is-ancestor", a, b])
    }

    /// Number of local commits not in `remote_ref`; None if the ref is unknown.
    pub fn ahead_of(&self, remote_ref: &str) -> Option<u32> {
        self.stdout(&["rev-list", "--count", &format!("{remote_ref}..HEAD")])?
            .parse()
            .ok()
    }

    pub fn ff_merge(&self, c: &str) -> anyhow::Result<()> {
        let out = self.run(&["merge", "--ff-only", c])?;
        if !out.status.success() {
            bail!(
                "git merge --ff-only {c} failed: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            );
        }
        Ok(())
    }
}
