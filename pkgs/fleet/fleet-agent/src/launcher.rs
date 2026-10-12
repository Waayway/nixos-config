//! Starts the apply wrapper outside the agent daemon.

use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{Context, bail};

use crate::config::{AgentConfig, Launcher};

/// The wrapper invocation: `<exe> apply --config <path> <id> <commit>`.
fn wrapper_args(config_path: &Path, id: &str, commit: &str) -> Vec<std::ffi::OsString> {
    vec![
        "apply".into(),
        "--config".into(),
        config_path.into(),
        id.into(),
        commit.into(),
    ]
}

pub fn launch(cfg: &AgentConfig, config_path: &Path, id: &str, commit: &str) -> anyhow::Result<()> {
    let exe = std::env::current_exe().context("locating own executable")?;
    let args = wrapper_args(config_path, id, commit);
    match cfg.launcher {
        Launcher::SystemdRun => {
            let unit = format!("fleet-apply-{}", &id[..id.len().min(8)]);
            let status = Command::new("systemd-run")
                .args(["--unit", &unit, "--collect", "--property=Type=exec"])
                .arg(&exe)
                .args(&args)
                .stdin(Stdio::null())
                .status()
                .context("running systemd-run")?;
            if !status.success() {
                bail!("systemd-run failed ({status})");
            }
        }
        Launcher::Detach => {
            let mut cmd = Command::new(&exe);
            cmd.args(&args)
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
            let child = Command::new(&exe)
                .args(&args)
                .spawn()
                .context("spawning apply wrapper")?;
            reap(child);
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
