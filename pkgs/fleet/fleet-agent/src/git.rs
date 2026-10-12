use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Output};

use anyhow::{Context, bail};
use nix::unistd::{Gid, Uid, User, setgid, setuid};

use crate::config::AgentConfig;

/// Element type `getgrouplist` fills: `c_int` on Apple, `gid_t` elsewhere.
#[cfg(target_vendor = "apple")]
type GroupElem = libc::c_int;
#[cfg(not(target_vendor = "apple"))]
type GroupElem = libc::gid_t;

/// The user's group list (including `gid`), resolved in the parent process.
/// `getgrouplist` may allocate and consult NSS, so it must not run after fork.
fn group_list(user: &std::ffi::CStr, gid: u32) -> std::io::Result<Vec<libc::gid_t>> {
    let mut buf: Vec<GroupElem> = vec![0; 32];
    loop {
        let mut n = buf.len() as libc::c_int;
        // SAFETY: `user` is NUL-terminated; `buf` holds `n` elements and `n` is
        // a valid out-pointer for the duration of the call.
        let rc = unsafe { libc::getgrouplist(user.as_ptr(), gid as _, buf.as_mut_ptr(), &mut n) };
        if rc >= 0 {
            buf.truncate(n as usize);
            return Ok(buf.into_iter().map(|g| g as libc::gid_t).collect());
        }
        // -1: buffer too small, `n` now holds the required size. Grow and retry
        // (always at least doubling, so a misbehaving libc cannot loop forever).
        let want = (n.max(0) as usize).max(buf.len() * 2);
        if want > 65536 {
            return Err(std::io::Error::other("getgrouplist: too many groups"));
        }
        buf.resize(want, 0);
    }
}

/// Caps a group list at `max` entries for `setgroups`, keeping `primary` first
/// when present. Apple's `setgroups` rejects more than `NGROUPS_MAX` (16)
/// entries with EINVAL, while `getgrouplist` can return more.
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
fn cap_groups(mut groups: Vec<libc::gid_t>, primary: libc::gid_t, max: usize) -> Vec<libc::gid_t> {
    if let Some(pos) = groups.iter().position(|&g| g == primary) {
        let g = groups.remove(pos);
        groups.insert(0, g);
    }
    groups.truncate(max);
    groups
}

/// Makes `cmd` run as `user` instead of root, with the user's own groups.
///
/// std applies `.uid()/.gid()` before `pre_exec` hooks, and root's supplementary
/// groups (wheel etc.) survive a plain uid/gid switch. So the whole drop happens
/// in one `pre_exec` hook, in the only safe order: supplementary groups first
/// (needs root), then gid, then uid (after which no further change is possible).
/// The group list is resolved before fork (see [`group_list`]); the hook itself
/// only issues the `setgroups`, `setgid` and `setuid` syscalls, which are
/// async-signal-safe and do not allocate.
pub fn drop_privileges(
    cmd: &mut Command,
    user: &str,
    uid: u32,
    gid: u32,
    home: &std::path::Path,
) -> std::io::Result<()> {
    let cuser = std::ffi::CString::new(user)
        .map_err(|_| std::io::Error::other("user name contains NUL"))?;
    let groups = group_list(&cuser, gid)?;
    #[cfg(target_vendor = "apple")]
    let groups = {
        // SAFETY: sysconf has no preconditions.
        let max = unsafe { libc::sysconf(libc::_SC_NGROUPS_MAX) };
        // Fallback: NGROUPS_MAX from <sys/syslimits.h> (not exported by libc).
        let max = if max > 0 { max as usize } else { 16 };
        cap_groups(groups, gid as libc::gid_t, max)
    };
    let (uid, gid) = (Uid::from_raw(uid), Gid::from_raw(gid));
    // SAFETY: the hook runs between fork and exec and calls only
    // async-signal-safe functions (setgroups, setgid, setuid) on data that was
    // fully prepared before the fork; it neither allocates nor takes locks.
    unsafe {
        cmd.pre_exec(move || {
            // `len as _`: the length parameter is size_t on Linux, c_int on Apple.
            if libc::setgroups(groups.len() as _, groups.as_ptr()) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            setgid(gid)?;
            setuid(uid)?;
            Ok(())
        });
    }
    cmd.env("HOME", home).env("USER", user).env("LOGNAME", user);
    Ok(())
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
            drop_privileges(&mut cmd, &self.user, *uid, *gid, home)
                .context("preparing privilege drop")?;
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

#[cfg(test)]
mod tests {
    use super::cap_groups;

    #[test]
    fn cap_groups_keeps_primary_first_and_truncates() {
        let groups: Vec<libc::gid_t> = (1..=20).collect();
        let capped = cap_groups(groups, 18, 16);
        assert_eq!(capped.len(), 16);
        assert_eq!(capped[0], 18);
        assert_eq!(&capped[1..], &(1..=15).collect::<Vec<_>>()[..]);
    }

    #[test]
    fn cap_groups_leaves_short_list_unchanged_when_primary_absent() {
        assert_eq!(cap_groups(vec![5, 6, 7], 1, 16), vec![5, 6, 7]);
    }
}
