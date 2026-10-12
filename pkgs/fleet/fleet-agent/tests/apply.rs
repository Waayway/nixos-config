mod common;
use common::*;
use fleet_agent::apply::{applies_dir, latest_record, prune, read_log, read_record, run_apply};
use fleet_agent::git::Git;
use fleet_proto::{ApplyRecord, ApplyState, SkipReason};

fn with_command(f: &mut Fixture, script: &str) {
    f.cfg.rebuild_command = Some(vec!["sh".into(), "-c".into(), script.into()]);
}

fn fetch_new_commit(f: &Fixture) -> String {
    let c = push_remote_commit(f, "b.txt");
    Git::new(&f.cfg).unwrap().fetch(&f.cfg.repo_url).unwrap();
    c
}

fn write_record(f: &Fixture, id: &str, state: ApplyState, started_at: i64) {
    let dir = applies_dir(&f.cfg);
    std::fs::create_dir_all(&dir).unwrap();
    let rec = ApplyRecord {
        apply_id: id.into(),
        commit: "0".repeat(40),
        state,
        skip_reason: None,
        message: None,
        exit_code: None,
        started_at: Some(started_at),
        finished_at: None,
    };
    std::fs::write(
        dir.join(format!("{id}.json")),
        serde_json::to_vec(&rec).unwrap(),
    )
    .unwrap();
}

#[test]
fn apply_ok_moves_head_and_records_ok() {
    let mut f = fixture();
    with_command(&mut f, "echo built $0 $1; exit 0");
    let c = fetch_new_commit(&f);
    let rec = run_apply(&f.cfg, "id-1", &c);
    assert_eq!(rec.state, ApplyState::Ok, "{rec:?}");
    assert_eq!(rec.exit_code, Some(0));
    assert!(rec.started_at.is_some() && rec.finished_at.is_some());
    assert_eq!(git(&f.clone, &["rev-parse", "HEAD"]), c);
    let log = read_log(&f.cfg, "id-1", 0).unwrap();
    assert!(log.data.contains(&format!("built h {c}")), "{}", log.data);
    assert!(!f.cfg.state_dir.join("apply-in-progress.json").exists());
    assert_eq!(read_record(&f.cfg, "id-1"), Some(rec));
}

#[test]
fn apply_skips_dirty_and_leaves_tree() {
    let mut f = fixture();
    with_command(&mut f, "echo built; exit 0");
    let c = fetch_new_commit(&f);
    let before = git(&f.clone, &["rev-parse", "HEAD"]);
    std::fs::write(f.clone.join("a.txt"), "changed").unwrap();
    let rec = run_apply(&f.cfg, "id-2", &c);
    assert_eq!(rec.state, ApplyState::Skipped);
    assert_eq!(rec.skip_reason, Some(SkipReason::Dirty));
    assert_eq!(git(&f.clone, &["rev-parse", "HEAD"]), before);
    assert!(!f.cfg.state_dir.join("apply-in-progress.json").exists());
}

#[test]
fn apply_failed_build_records_exit_code() {
    let mut f = fixture();
    with_command(&mut f, "echo nope >&2; exit 3");
    let c = fetch_new_commit(&f);
    let rec = run_apply(&f.cfg, "id-3", &c);
    assert_eq!(rec.state, ApplyState::Failed);
    assert_eq!(rec.exit_code, Some(3));
    assert_eq!(git(&f.clone, &["rev-parse", "HEAD"]), c);
    assert!(read_log(&f.cfg, "id-3", 0).unwrap().data.contains("nope"));
}

#[test]
fn apply_rejects_invalid_commit() {
    let mut f = fixture();
    with_command(&mut f, "exit 0");
    let rec = run_apply(&f.cfg, "id-4", "--upload-pack=evil");
    assert_eq!(rec.state, ApplyState::Failed);
    assert_eq!(rec.message.as_deref(), Some("invalid commit"));
}

#[test]
fn apply_fetch_failure_is_skipped() {
    let mut f = fixture();
    with_command(&mut f, "exit 0");
    f.cfg.repo_url = f.cfg.state_dir.join("missing.git").to_string_lossy().into();
    let rec = run_apply(&f.cfg, "id-5", &"a".repeat(40));
    assert_eq!(rec.state, ApplyState::Skipped);
    assert_eq!(rec.skip_reason, Some(SkipReason::FetchFailed));
}

#[test]
fn interrupted_running_record_reports_failed() {
    let f = fixture();
    write_record(&f, "dead", ApplyState::Running, 100);
    let mut child = std::process::Command::new("true").spawn().unwrap();
    let pid = child.id();
    child.wait().unwrap();
    std::fs::write(applies_dir(&f.cfg).join("dead.pid"), pid.to_string()).unwrap();
    let rec = latest_record(&f.cfg).unwrap();
    assert_eq!(rec.apply_id, "dead");
    assert_eq!(rec.state, ApplyState::Failed);
    assert_eq!(rec.message.as_deref(), Some("interrupted"));
}

#[test]
fn running_record_with_live_pid_stays_running() {
    let f = fixture();
    write_record(&f, "live", ApplyState::Running, 100);
    std::fs::write(
        applies_dir(&f.cfg).join("live.pid"),
        std::process::id().to_string(),
    )
    .unwrap();
    assert_eq!(latest_record(&f.cfg).unwrap().state, ApplyState::Running);
}

#[test]
fn latest_record_is_newest_by_started_at() {
    let f = fixture();
    write_record(&f, "old", ApplyState::Ok, 10);
    write_record(&f, "new", ApplyState::Ok, 20);
    assert_eq!(latest_record(&f.cfg).unwrap().apply_id, "new");
    assert_eq!(latest_record(&fixture().cfg), None);
}

#[test]
fn prune_keeps_50() {
    let f = fixture();
    for i in 0..60 {
        let id = format!("a{i:02}");
        write_record(&f, &id, ApplyState::Ok, i);
        std::fs::write(applies_dir(&f.cfg).join(format!("{id}.log")), "x").unwrap();
    }
    prune(&f.cfg, 50);
    let json = |n: &str| applies_dir(&f.cfg).join(format!("{n}.json")).exists();
    let log = |n: &str| applies_dir(&f.cfg).join(format!("{n}.log")).exists();
    assert!(!json("a00") && !log("a09") && !json("a09"));
    assert!(json("a10") && log("a10") && json("a59"));
    let count = std::fs::read_dir(applies_dir(&f.cfg))
        .unwrap()
        .filter(|e| {
            e.as_ref()
                .unwrap()
                .path()
                .extension()
                .is_some_and(|x| x == "json")
        })
        .count();
    assert_eq!(count, 50);
}

#[test]
fn read_log_offset() {
    let f = fixture();
    write_record(&f, "r", ApplyState::Ok, 1);
    std::fs::write(applies_dir(&f.cfg).join("r.log"), "hello world").unwrap();
    let c = read_log(&f.cfg, "r", 6).unwrap();
    assert_eq!((c.data.as_str(), c.offset, c.eof), ("world", 6, true));
    let c = read_log(&f.cfg, "r", 100).unwrap();
    assert_eq!((c.data.as_str(), c.eof), ("", true));
    assert!(read_log(&f.cfg, "missing", 0).is_none());
    assert!(read_log(&f.cfg, "../r", 0).is_none());
}

#[test]
fn read_log_not_eof_while_running() {
    let f = fixture();
    write_record(&f, "run", ApplyState::Running, 1);
    std::fs::write(
        applies_dir(&f.cfg).join("run.pid"),
        std::process::id().to_string(),
    )
    .unwrap();
    std::fs::write(applies_dir(&f.cfg).join("run.log"), "partial").unwrap();
    let c = read_log(&f.cfg, "run", 0).unwrap();
    assert_eq!((c.data.as_str(), c.eof), ("partial", false));
}

#[test]
fn read_log_does_not_split_multibyte_char_while_running() {
    let f = fixture();
    write_record(&f, "mb", ApplyState::Running, 1);
    let dir = applies_dir(&f.cfg);
    std::fs::write(dir.join("mb.pid"), std::process::id().to_string()).unwrap();
    // "a" then the first byte of "é" (c3 a9).
    std::fs::write(dir.join("mb.log"), [b'a', 0xc3]).unwrap();
    let c = read_log(&f.cfg, "mb", 0).unwrap();
    assert_eq!((c.data.as_str(), c.eof), ("a", false));
    std::fs::write(dir.join("mb.log"), [b'a', 0xc3, 0xa9]).unwrap();
    let next = c.offset + c.data.len() as u64;
    let c = read_log(&f.cfg, "mb", next).unwrap();
    assert_eq!(c.data, "é");
}

#[test]
fn launch_command_rejects_bad_input() {
    use fleet_agent::launcher::launch_command;
    let f = fixture();
    let p = std::path::Path::new("/c.json");
    let ok = "a".repeat(40);
    assert!(launch_command(&f.cfg, p, "-x", &ok).is_err());
    assert!(launch_command(&f.cfg, p, "ééééé", &ok).is_err());
    assert!(launch_command(&f.cfg, p, "id", "--evil").is_err());
}

#[test]
fn launch_command_systemd_run_argv() {
    use fleet_agent::config::Launcher;
    use fleet_agent::launcher::{DAEMON_PATH, launch_command};
    let mut f = fixture();
    f.cfg.launcher = Launcher::SystemdRun;
    f.cfg.agent_exe = Some("/bin/fa".into());
    let c = "b".repeat(40);
    let (prog, args) =
        launch_command(&f.cfg, std::path::Path::new("/c.json"), "12345678-90", &c).unwrap();
    assert_eq!(prog.to_str(), Some("systemd-run"));
    let want = [
        "--unit",
        "fleet-apply-12345678",
        "--collect",
        "--property=Type=exec",
        &format!("--setenv=PATH={DAEMON_PATH}"),
        "--setenv=HOME=/root",
        "/bin/fa",
        "apply",
        "--config",
        "/c.json",
        "--",
        "12345678-90",
        &c,
    ];
    assert_eq!(args, want);
}

#[test]
fn launch_command_detach_uses_agent_exe() {
    use fleet_agent::config::Launcher;
    use fleet_agent::launcher::launch_command;
    let mut f = fixture();
    f.cfg.launcher = Launcher::Detach;
    f.cfg.agent_exe = Some("/bin/fa".into());
    let c = "b".repeat(40);
    let (prog, args) = launch_command(&f.cfg, std::path::Path::new("/c.json"), "id1", &c).unwrap();
    assert_eq!(prog.to_str(), Some("/bin/fa"));
    assert_eq!(args, ["apply", "--config", "/c.json", "--", "id1", &c]);
}
