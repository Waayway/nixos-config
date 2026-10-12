//! The apply wrapper body and the state files it leaves for the agent daemon.
//!
//! Layout under `<state_dir>`: `apply-in-progress.json` while an apply runs,
//! and `applies/<id>.{json,log,pid}` per apply.

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Context;
use fleet_proto::{ApplyRecord, ApplyState, LogChunk, SkipReason, is_commit_hash};

use crate::checks::check_apply;
use crate::config::AgentConfig;
use crate::git::Git;

const SYSTEM_PROFILE: &str = "/nix/var/nix/profiles/system";

/// Exclusive, non-blocking lock on `<state_dir>/apply.lock`; held (by the
/// returned file) for as long as an apply runs. None if another holds it.
pub fn try_lock_apply(cfg: &AgentConfig) -> Option<File> {
    use std::os::fd::AsRawFd;
    fs::create_dir_all(&cfg.state_dir).ok()?;
    let f = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(cfg.state_dir.join("apply.lock"))
        .ok()?;
    // SAFETY: flock on a descriptor we own.
    (unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0).then_some(f)
}

/// Records a successful fetch in `<state_dir>/last_fetch` (unix seconds).
pub fn record_fetch(cfg: &AgentConfig) {
    let _ = fs::create_dir_all(&cfg.state_dir);
    let _ = fs::write(cfg.state_dir.join("last_fetch"), now().to_string());
}

pub fn applies_dir(cfg: &AgentConfig) -> PathBuf {
    cfg.state_dir.join("applies")
}

/// Apply ids become file names, so anything that could escape the directory
/// is refused.
pub fn is_valid_apply_id(id: &str) -> bool {
    id.bytes().next().is_some_and(|b| b.is_ascii_alphanumeric())
        && id.len() <= 64
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn file(cfg: &AgentConfig, id: &str, ext: &str) -> PathBuf {
    applies_dir(cfg).join(format!("{id}.{ext}"))
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Writes `path` atomically: a temporary sibling, then a rename.
fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut tmp = path.as_os_str().to_owned();
    tmp.push(".tmp");
    let tmp = PathBuf::from(tmp);
    fs::write(&tmp, bytes)?;
    fs::rename(&tmp, path)
}

fn write_record(cfg: &AgentConfig, rec: &ApplyRecord) -> anyhow::Result<()> {
    write_atomic(&file(cfg, &rec.apply_id, "json"), &serde_json::to_vec(rec)?)
        .with_context(|| format!("writing record {}", rec.apply_id))
}

/// True unless `pid` is known not to exist (`ESRCH`).
fn pid_alive(pid: i32) -> bool {
    // SAFETY: signal 0 only checks that the process exists.
    if unsafe { libc::kill(pid, 0) } == 0 {
        return true;
    }
    std::io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH)
}

/// The stored record, with a `Running` record whose wrapper died reported as
/// failed ("interrupted").
pub fn read_record(cfg: &AgentConfig, id: &str) -> Option<ApplyRecord> {
    if !is_valid_apply_id(id) {
        return None;
    }
    let raw = fs::read(file(cfg, id, "json")).ok()?;
    let mut rec: ApplyRecord = serde_json::from_slice(&raw).ok()?;
    if rec.state == ApplyState::Running {
        let alive = fs::read_to_string(file(cfg, id, "pid"))
            .ok()
            .and_then(|s| s.trim().parse::<i32>().ok())
            .is_some_and(pid_alive);
        if !alive {
            rec.state = ApplyState::Failed;
            rec.message = Some("interrupted".into());
        }
    }
    Some(rec)
}

fn record_ids(cfg: &AgentConfig) -> Vec<String> {
    let Ok(rd) = fs::read_dir(applies_dir(cfg)) else {
        return vec![];
    };
    rd.filter_map(|e| {
        let p = e.ok()?.path();
        if p.extension()? != "json" {
            return None;
        }
        let id = p.file_stem()?.to_str()?.to_string();
        is_valid_apply_id(&id).then_some(id)
    })
    .collect()
}

/// Records, newest first (by `started_at`, then id).
fn records_newest_first(cfg: &AgentConfig) -> Vec<ApplyRecord> {
    let mut recs: Vec<ApplyRecord> = record_ids(cfg)
        .iter()
        .filter_map(|id| read_record(cfg, id))
        .collect();
    recs.sort_by(|a, b| (b.started_at, &b.apply_id).cmp(&(a.started_at, &a.apply_id)));
    recs
}

pub fn latest_record(cfg: &AgentConfig) -> Option<ApplyRecord> {
    records_newest_first(cfg).into_iter().next()
}

/// Log bytes from `offset` on. `eof` is true once the apply has finished and
/// the chunk reaches the end of the log. `offset` echoes the request; the next
/// request continues at `offset + data.len()`.
pub fn read_log(cfg: &AgentConfig, id: &str, offset: u64) -> Option<LogChunk> {
    let rec = read_record(cfg, id)?;
    let mut buf = Vec::new();
    let mut at_end = true;
    if let Ok(mut f) = File::open(file(cfg, id, "log")) {
        let len = f.metadata().ok()?.len();
        if offset < len {
            f.seek(SeekFrom::Start(offset)).ok()?;
            f.read_to_end(&mut buf).ok()?;
        }
        at_end = offset + buf.len() as u64 >= len;
    }
    let eof = at_end && rec.state != ApplyState::Running;
    let data = match std::str::from_utf8(&buf) {
        Ok(s) => s.to_string(),
        // A multibyte char cut off by the end of a still-growing log: leave it
        // for the next read so `data.len()` stays the number of bytes consumed.
        Err(e) if !eof && e.error_len().is_none() => {
            String::from_utf8_lossy(&buf[..e.valid_up_to()]).into_owned()
        }
        Err(_) => String::from_utf8_lossy(&buf).into_owned(),
    };
    Some(LogChunk {
        apply_id: id.to_string(),
        offset,
        data,
        eof,
    })
}

/// Deletes all but the newest `keep` applies (never one still running).
pub fn prune(cfg: &AgentConfig, keep: usize) {
    for rec in records_newest_first(cfg).into_iter().skip(keep) {
        if rec.state == ApplyState::Running {
            continue;
        }
        for ext in ["json", "log", "pid"] {
            let _ = fs::remove_file(file(cfg, &rec.apply_id, ext));
        }
    }
}

enum Outcome {
    Ok,
    Skipped(SkipReason, String),
    Failed(Option<i32>, String),
}

struct Log(File);

impl Log {
    fn line(&mut self, s: &str) {
        let _ = writeln!(self.0, "==> {s}");
    }

    fn stdio(&self) -> anyhow::Result<(Stdio, Stdio)> {
        Ok((
            Stdio::from(self.0.try_clone()?),
            Stdio::from(self.0.try_clone()?),
        ))
    }

    /// Runs `cmd` with stdout and stderr appended to the log.
    fn run(&mut self, what: &str, cmd: &mut Command) -> Result<(), Outcome> {
        self.line(what);
        let fail = |e: String| Outcome::Failed(None, e);
        let (out, err) = self.stdio().map_err(|e| fail(e.to_string()))?;
        let status = cmd
            .stdin(Stdio::null())
            .stdout(out)
            .stderr(err)
            .status()
            .map_err(|e| fail(format!("{what}: {e}")))?;
        self.finish(what, status)
    }

    fn finish(&mut self, what: &str, status: std::process::ExitStatus) -> Result<(), Outcome> {
        if status.success() {
            return Ok(());
        }
        let msg = format!("{what} failed ({status})");
        self.line(&msg);
        Err(Outcome::Failed(status.code(), msg))
    }
}

/// Steps 5-6: build as the user, then switch as root (or the test command).
fn build_and_switch(
    cfg: &AgentConfig,
    git: &Git,
    commit: &str,
    log: &mut Log,
) -> Result<(), Outcome> {
    if let Some(cmd) = &cfg.rebuild_command {
        let (prog, args) = cmd
            .split_first()
            .ok_or_else(|| Outcome::Failed(None, "rebuild_command is empty".into()))?;
        let mut c = Command::new(prog);
        c.args(args).arg(&cfg.host).arg(commit);
        return log.run("rebuild command", &mut c);
    }

    let attr = if cfg.os == "darwin" {
        format!("darwinConfigurations.{}.system", cfg.host)
    } else {
        format!(
            "nixosConfigurations.{}.config.system.build.toplevel",
            cfg.host
        )
    };
    let fail = |e: String| Outcome::Failed(None, e);
    log.line("nix build");
    let mut build = git.user_command("nix").map_err(|e| fail(e.to_string()))?;
    build
        .args(["build", "--no-link", "--print-out-paths"])
        .arg(format!("{}#{attr}", cfg.flake_path.display()))
        .stdin(Stdio::null())
        .stderr(log.stdio().map_err(|e| fail(e.to_string()))?.1);
    let out = build
        .output()
        .map_err(|e| fail(format!("nix build: {e}")))?;
    let _ = log.0.write_all(&out.stdout);
    log.finish("nix build", out.status)?;
    let store_path = String::from_utf8_lossy(&out.stdout)
        .lines()
        .last()
        .unwrap_or("")
        .trim()
        .to_string();
    if !store_path.starts_with("/nix/store/") {
        return Err(fail("nix build printed no store path".into()));
    }

    log.run(
        "nix-env --set",
        Command::new("nix-env").args(["-p", SYSTEM_PROFILE, "--set", &store_path]),
    )?;
    let (what, mut switch) = if cfg.os == "darwin" {
        ("activate", Command::new(format!("{store_path}/activate")))
    } else {
        let mut c = Command::new(format!("{store_path}/bin/switch-to-configuration"));
        c.arg("switch").env_remove("NIXOS_INSTALL_BOOTLOADER");
        ("switch-to-configuration", c)
    };
    log.run(what, &mut switch)
}

fn steps(cfg: &AgentConfig, commit: &str, log: &mut Log) -> Outcome {
    let git = match Git::new(cfg) {
        Ok(g) => g,
        Err(e) => return Outcome::Failed(None, format!("{e:#}")),
    };
    log.line("git fetch");
    if let Err(e) = git.fetch(&cfg.repo_url) {
        let msg = format!("{e:#}");
        log.line(&msg);
        return Outcome::Skipped(SkipReason::FetchFailed, msg);
    }
    record_fetch(cfg);
    log.line("checks");
    if let Err(reason) = check_apply(&git, &cfg.channel, commit) {
        let msg = format!("skipped: {reason:?}");
        log.line(&msg);
        return Outcome::Skipped(reason, msg);
    }
    log.line("git merge --ff-only");
    if let Err(e) = git.ff_merge(commit) {
        let msg = format!("{e:#}");
        log.line(&msg);
        return Outcome::Failed(None, msg);
    }
    match build_and_switch(cfg, &git, commit, log) {
        Ok(()) => Outcome::Ok,
        Err(o) => o,
    }
}

/// The wrapper body: runs the whole apply, keeping `<id>.json` current.
pub fn run_apply(cfg: &AgentConfig, id: &str, commit: &str) -> ApplyRecord {
    let mut rec = ApplyRecord {
        apply_id: id.to_string(),
        commit: commit.to_string(),
        state: ApplyState::Failed,
        skip_reason: None,
        message: None,
        exit_code: None,
        started_at: Some(now()),
        finished_at: None,
    };
    if !is_valid_apply_id(id) {
        rec.message = Some("invalid apply id".into());
        return rec;
    }
    // Held until the function returns; keeps a second wrapper out.
    let Some(_lock) = try_lock_apply(cfg) else {
        eprintln!("fleet-agent: another apply is running; not starting {id}");
        rec.message = Some("another apply is running".into());
        return rec;
    };
    if let Err(e) = start(cfg, &mut rec) {
        rec.message = Some(format!("{e:#}"));
        rec.finished_at = Some(now());
        return rec;
    }
    let in_progress = cfg.state_dir.join("apply-in-progress.json");

    let outcome = if !is_commit_hash(commit) {
        Outcome::Failed(None, "invalid commit".into())
    } else {
        match OpenOptions::new()
            .create(true)
            .append(true)
            .open(file(cfg, id, "log"))
        {
            Ok(f) => steps(cfg, commit, &mut Log(f)),
            Err(e) => Outcome::Failed(None, format!("opening log: {e}")),
        }
    };
    match outcome {
        Outcome::Ok => {
            rec.state = ApplyState::Ok;
            rec.exit_code = Some(0);
        }
        Outcome::Skipped(reason, msg) => {
            rec.state = ApplyState::Skipped;
            rec.skip_reason = Some(reason);
            rec.message = Some(msg);
        }
        Outcome::Failed(code, msg) => {
            rec.state = ApplyState::Failed;
            rec.exit_code = code;
            rec.message = Some(msg);
        }
    }
    rec.finished_at = Some(now());
    if let Err(e) = write_record(cfg, &rec) {
        eprintln!("fleet-agent: {e:#}");
    }
    let _ = fs::remove_file(in_progress);
    let _ = fs::remove_file(file(cfg, id, "pid"));
    prune(cfg, 50);
    rec
}

/// Step 1: pid file, in-progress marker and the `Running` record.
fn start(cfg: &AgentConfig, rec: &mut ApplyRecord) -> anyhow::Result<()> {
    fs::create_dir_all(applies_dir(cfg)).context("creating applies dir")?;
    // The pid goes first, so a `Running` record is never seen without it.
    fs::write(
        file(cfg, &rec.apply_id, "pid"),
        std::process::id().to_string(),
    )
    .context("writing pid file")?;
    let marker = serde_json::json!({
        "apply_id": rec.apply_id,
        "commit": rec.commit,
        "started": rec.started_at,
    });
    write_atomic(
        &cfg.state_dir.join("apply-in-progress.json"),
        marker.to_string().as_bytes(),
    )
    .context("writing apply-in-progress.json")?;
    rec.state = ApplyState::Running;
    write_record(cfg, rec)?;
    Ok(())
}
