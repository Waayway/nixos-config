//! Starts the apply wrapper outside the agent daemon.

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, bail};
use fleet_proto::is_commit_hash;

use crate::apply::is_valid_apply_id;
use crate::config::{AgentConfig, Launcher};

/// The daemon PATH (global constraints); transient units do not inherit it.
pub const DAEMON_PATH: &str =
    "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";

/// Root's home directory for the wrapper: `/var/root` on macOS, `/root` elsewhere.
pub fn daemon_home(cfg: &AgentConfig) -> &'static str {
    if cfg.os == "darwin" {
        "/var/root"
    } else {
        "/root"
    }
}

fn exe_path(cfg: &AgentConfig) -> anyhow::Result<PathBuf> {
    match &cfg.agent_exe {
        Some(p) => Ok(p.clone()),
        None => std::env::current_exe().context("locating own executable"),
    }
}

/// Program and argv for starting the wrapper. Pure, so it can be unit-tested.
/// `--` keeps a hostile positional from being parsed as a flag.
pub fn launch_command(
    cfg: &AgentConfig,
    config_path: &Path,
    id: &str,
    commit: &str,
) -> anyhow::Result<(PathBuf, Vec<String>)> {
    if !is_valid_apply_id(id) {
        bail!("invalid apply id");
    }
    if !is_commit_hash(commit) {
        bail!("invalid commit");
    }
    let exe = exe_path(cfg)?;
    let wrapper = [
        "apply".to_string(),
        "--config".into(),
        config_path.to_string_lossy().into_owned(),
        "--".into(),
        id.into(),
        commit.into(),
    ];
    Ok(match cfg.launcher {
        Launcher::SystemdRun => {
            let mut args = vec![
                "--unit".to_string(),
                format!("fleet-apply-{}", &id[..id.len().min(8)]),
                "--collect".into(),
                "--property=Type=exec".into(),
                format!("--setenv=PATH={DAEMON_PATH}"),
                format!("--setenv=HOME={}", daemon_home(cfg)),
                exe.to_string_lossy().into_owned(),
            ];
            args.extend(wrapper);
            (PathBuf::from("systemd-run"), args)
        }
        Launcher::Detach | Launcher::Inline => (exe, wrapper.to_vec()),
    })
}

pub fn launch(cfg: &AgentConfig, config_path: &Path, id: &str, commit: &str) -> anyhow::Result<()> {
    let (program, args) = launch_command(cfg, config_path, id, commit)?;
    let mut cmd = Command::new(program);
    cmd.args(args);
    match cfg.launcher {
        Launcher::SystemdRun => {
            let status = cmd
                .stdin(Stdio::null())
                .status()
                .context("running systemd-run")?;
            if !status.success() {
                bail!("systemd-run failed ({status})");
            }
        }
        Launcher::Detach => {
            cmd.env("PATH", DAEMON_PATH)
                .env("HOME", daemon_home(cfg))
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            // SAFETY: setsid is async-signal-safe and the hook does nothing else.
            unsafe {
                cmd.pre_exec(|| {
                    if libc::setsid() == -1 {
                        return Err(std::io::Error::last_os_error());
                    }
                    Ok(())
                });
            }
            reap(cmd.spawn().context("spawning apply wrapper")?);
        }
        Launcher::Inline => {
            cmd.env("PATH", DAEMON_PATH).env("HOME", daemon_home(cfg));
            reap(cmd.spawn().context("spawning apply wrapper")?);
        }
    }
    Ok(())
}

/// Waits for the child in the background so it never lingers as a zombie.
fn reap(mut child: std::process::Child) {
    std::thread::spawn(move || {
        let _ = child.wait();
    });
}
