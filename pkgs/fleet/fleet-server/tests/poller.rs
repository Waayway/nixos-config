//! Poller against in-process fake agents (axum on 127.0.0.1:0).

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use fleet_proto::{
    ActivationEvent, ActivationsResponse, AgentStatus, ApplyRecord, ApplyRequest, ApplyState,
    CheckoutStatus, LogChunk, OnlineState, WsMessage,
};
use fleet_server::config::{AccessConfig, FleetHost, OnlineSource, ServerConfig};
use fleet_server::db;
use fleet_server::mirror::Mirror;
use fleet_server::poller::poll_once;
use fleet_server::state::AppState;
use fleet_server::tailscale::{Identity, OnlineProvider, PeerInfo, StaticOnline};
use serde::Deserialize;

const OLD: &str = "0000000000000000000000000000000000000000";
const NEW: &str = "1111111111111111111111111111111111111111";

#[derive(Default)]
struct Fake {
    status: Option<AgentStatus>,
    activations: Vec<ActivationEvent>,
    applied: Vec<ApplyRequest>,
    status_hits: u32,
    log: String,
    /// `/apply/log` answers 500 this many times first.
    log_failures: u32,
    /// When non-empty: successive (log bytes so far, finished) states, one per `/apply/log`
    /// call (the last one repeats). Overrides `log`.
    log_script: Vec<(Vec<u8>, bool)>,
    log_hits: u32,
    /// The offsets `/apply/log` was asked for.
    log_offsets: Vec<u64>,
}

type Shared = Arc<Mutex<Fake>>;

#[derive(Deserialize)]
struct Since {
    since: u64,
}

#[derive(Deserialize)]
struct LogQ {
    apply_id: String,
    offset: u64,
}

async fn fake_agent(fake: Shared) -> SocketAddr {
    /// `503` while `status` is unset.
    async fn status(State(f): State<Shared>) -> Result<Json<AgentStatus>, StatusCode> {
        let mut f = f.lock().unwrap();
        f.status_hits += 1;
        f.status
            .clone()
            .map(Json)
            .ok_or(StatusCode::SERVICE_UNAVAILABLE)
    }
    async fn activations(
        State(f): State<Shared>,
        Query(q): Query<Since>,
    ) -> Json<ActivationsResponse> {
        let f = f.lock().unwrap();
        Json(ActivationsResponse {
            events: f
                .activations
                .iter()
                .skip(q.since as usize)
                .cloned()
                .collect(),
            next: f.activations.len() as u64,
        })
    }
    async fn apply(State(f): State<Shared>, Json(req): Json<ApplyRequest>) -> StatusCode {
        f.lock().unwrap().applied.push(req);
        StatusCode::ACCEPTED
    }
    async fn log(
        State(f): State<Shared>,
        Query(q): Query<LogQ>,
    ) -> Result<Json<LogChunk>, StatusCode> {
        let mut f = f.lock().unwrap();
        f.log_hits += 1;
        f.log_offsets.push(q.offset);
        if f.log_failures > 0 {
            f.log_failures -= 1;
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
        let (full, eof) = if f.log_script.is_empty() {
            (f.log.clone().into_bytes(), true)
        } else if f.log_script.len() == 1 {
            f.log_script[0].clone()
        } else {
            f.log_script.remove(0)
        };
        // Like the real agent: raw bytes from `offset`, invalid UTF-8 replaced.
        let raw = full.get(q.offset as usize..).unwrap_or_default();
        Ok(Json(LogChunk {
            apply_id: q.apply_id,
            offset: q.offset,
            data: String::from_utf8_lossy(raw).into_owned(),
            next: q.offset + raw.len() as u64,
            eof,
        }))
    }
    let app = Router::new()
        .route("/status", get(status))
        .route("/activations", get(activations))
        .route("/apply", post(apply))
        .route("/apply/log", get(log))
        .with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    addr
}

fn agent_status(running: &str, apply: Option<ApplyRecord>) -> AgentStatus {
    AgentStatus {
        host: "h1".into(),
        os: "nixos".into(),
        agent_version: "0.1.0".into(),
        running: running.into(),
        checkout: CheckoutStatus {
            branch: Some("main".into()),
            head: None,
            dirty: false,
            untracked: 0,
            ahead: None,
            last_fetch_at: None,
        },
        apply,
    }
}

fn record(id: &str, commit: &str, state: ApplyState) -> ApplyRecord {
    ApplyRecord {
        apply_id: id.into(),
        commit: commit.into(),
        state,
        skip_reason: None,
        message: None,
        exit_code: None,
        started_at: None,
        finished_at: None,
    }
}

fn activation(line: u64) -> ActivationEvent {
    ActivationEvent {
        line,
        time: 1000 + line as i64,
        store_path: format!("/nix/store/{line}-system"),
        revision: OLD.into(),
        generation: Some(line),
        trigger: "manual".into(),
        sudo_user: Some("thijs".into()),
    }
}

fn host() -> FleetHost {
    FleetHost {
        name: "H1".into(),
        system: "x86_64-linux".into(),
        user: "u".into(),
        channel: "main".into(),
        os: "nixos".into(),
    }
}

fn empty_origin(dir: &Path) -> PathBuf {
    let bare = dir.join("origin.git");
    let out = Command::new("git")
        .args(["init", "--bare", "--quiet", bare.to_str().unwrap()])
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert!(out.status.success());
    bare
}

struct Env {
    state: AppState,
    _dir: tempfile::TempDir,
}

async fn env(agent: SocketAddr, online: Option<Arc<dyn OnlineProvider>>) -> Env {
    let dir = tempfile::tempdir().unwrap();
    let origin = empty_origin(dir.path());
    let addresses = HashMap::from([("h1".to_string(), agent.to_string())]);
    let cfg = ServerConfig {
        listen: "127.0.0.1:0".parse().unwrap(),
        agent_port: 7461,
        hosts_file: dir.path().join("hosts.json"),
        repo_url: origin.to_str().unwrap().into(),
        push_url: origin.to_str().unwrap().into(),
        deploy_key_file: None,
        state_dir: dir.path().join("state"),
        access: AccessConfig::Disabled,
        online: OnlineSource::Static {
            addresses: addresses.clone(),
        },
        mirror_fetch_secs: 300,
        poll_secs: 60,
        tailscale_bin: PathBuf::from("tailscale"),
    };
    let conn = db::connect(&cfg.state_dir).await.unwrap();
    let mirror = Arc::new(Mirror::open_or_init(&cfg).await.unwrap());
    let online = online.unwrap_or_else(|| Arc::new(StaticOnline::new(&addresses).unwrap()));
    let state = AppState::new(Arc::new(cfg), conn, mirror, online, vec![host()]).unwrap();
    Env { state, _dir: dir }
}

fn count_kind(events: &[fleet_proto::AuditEvent], kind: &str) -> usize {
    events.iter().filter(|e| e.kind == kind).count()
}

#[tokio::test]
async fn poll_saves_status_and_ingests_activations_once() {
    let fake = Shared::default();
    {
        let mut f = fake.lock().unwrap();
        f.status = Some(agent_status(OLD, None));
        f.activations = vec![activation(0), activation(1)];
    }
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    let mut rx = e.state.tx.subscribe();

    poll_once(&e.state).await;
    poll_once(&e.state).await;

    let (saved, ok_at) = db::load_status(&e.state.db, "H1").await.unwrap().unwrap();
    assert_eq!(saved.running, OLD);
    assert!(ok_at.is_some());
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    assert_eq!(count_kind(&audit, "activation"), 2, "{audit:?}");
    assert_eq!(db::activations_next(&e.state.db, "H1").await.unwrap(), 2);
    assert_eq!(fake.lock().unwrap().status_hits, 2);

    match rx.recv().await.unwrap() {
        WsMessage::HostUpdated(hv) => {
            assert_eq!(hv.name, "H1");
            assert_eq!(hv.online, OnlineState::On);
            assert_eq!(hv.running.as_deref(), Some(OLD));
            assert_eq!(hv.last_activation.map(|a| a.line), Some(1));
        }
        other => panic!("unexpected {other:?}"),
    }
}

#[tokio::test]
async fn poll_resends_missed_apply() {
    let fake = Shared::default();
    fake.lock().unwrap().status = Some(agent_status(OLD, Some(record("a0", OLD, ApplyState::Ok))));
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Idle),
    )
    .await
    .unwrap();
    db::set_desired(&e.state.db, "H1", "a1").await.unwrap();

    poll_once(&e.state).await;

    assert_eq!(
        fake.lock().unwrap().applied,
        vec![ApplyRequest {
            apply_id: "a1".into(),
            commit: NEW.into()
        }]
    );
}

#[tokio::test]
async fn poll_does_not_resend_failed() {
    let fake = Shared::default();
    {
        let mut f = fake.lock().unwrap();
        let mut rec = record("a1", NEW, ApplyState::Failed);
        rec.exit_code = Some(1);
        rec.finished_at = Some(50);
        f.status = Some(agent_status(OLD, Some(rec)));
        f.log = "building...\nerror: boom\n".into();
    }
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Running),
    )
    .await
    .unwrap();
    db::set_desired(&e.state.db, "H1", "a1").await.unwrap();

    poll_once(&e.state).await;
    poll_once(&e.state).await;

    assert!(fake.lock().unwrap().applied.is_empty());
    let row = db::get_apply(&e.state.db, "a1").await.unwrap().unwrap();
    assert_eq!(row.state, "failed");
    assert_eq!(row.exit_code, Some(1));
    assert_eq!(row.log.as_deref(), Some("building...\nerror: boom\n"));
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    assert_eq!(count_kind(&audit, "apply_finished"), 1, "{audit:?}");
    let finished = audit.iter().find(|a| a.kind == "apply_finished").unwrap();
    assert_eq!(finished.actor, "agent");
    assert_eq!(finished.host.as_deref(), Some("H1"));
    assert_eq!(finished.details["apply_id"], "a1");
}

/// Tailscale reports the host offline (but with an address).
struct Offline;

#[async_trait::async_trait]
impl OnlineProvider for Offline {
    async fn peers(&self) -> HashMap<String, PeerInfo> {
        HashMap::from([(
            "h1".to_string(),
            PeerInfo {
                host: "h1".into(),
                online: false,
                last_seen: Some(42),
                os: "linux".into(),
                addr: Some(IpAddr::from([127, 0, 0, 1])),
            },
        )])
    }
    async fn whois(&self, _ip: IpAddr) -> Option<Identity> {
        None
    }
}

#[tokio::test]
async fn offline_host_not_contacted() {
    let fake = Shared::default();
    fake.lock().unwrap().status = Some(agent_status(OLD, None));
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, Some(Arc::new(Offline))).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Idle),
    )
    .await
    .unwrap();
    db::set_desired(&e.state.db, "H1", "a1").await.unwrap();
    let mut rx = e.state.tx.subscribe();

    poll_once(&e.state).await;

    {
        let f = fake.lock().unwrap();
        assert_eq!(f.status_hits, 0);
        assert!(f.applied.is_empty());
    }
    match rx.recv().await.unwrap() {
        WsMessage::HostUpdated(hv) => {
            assert_eq!(hv.online, OnlineState::Off);
            assert_eq!(hv.last_seen, Some(42));
        }
        other => panic!("unexpected {other:?}"),
    }
}

#[tokio::test]
async fn apply_finished_retried_when_log_fetch_fails() {
    let fake = Shared::default();
    {
        let mut f = fake.lock().unwrap();
        f.status = Some(agent_status(
            OLD,
            Some(record("a1", NEW, ApplyState::Failed)),
        ));
        f.log = "error: boom\n".into();
        f.log_failures = 1;
    }
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Running),
    )
    .await
    .unwrap();

    poll_once(&e.state).await;
    let row = db::get_apply(&e.state.db, "a1").await.unwrap().unwrap();
    assert_eq!(row.state, "running");
    assert_eq!(row.log, None);
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    assert_eq!(count_kind(&audit, "apply_finished"), 0, "{audit:?}");

    poll_once(&e.state).await;
    poll_once(&e.state).await;
    let row = db::get_apply(&e.state.db, "a1").await.unwrap().unwrap();
    assert_eq!(row.state, "failed");
    assert_eq!(row.log.as_deref(), Some("error: boom\n"));
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    assert_eq!(count_kind(&audit, "apply_finished"), 1, "{audit:?}");
}

#[tokio::test]
async fn follow_log_streams_running_apply_once() {
    let fake = Shared::default();
    {
        let mut f = fake.lock().unwrap();
        f.status = Some(agent_status(
            OLD,
            Some(record("a1", NEW, ApplyState::Running)),
        ));
        f.log_script = vec![
            ("one\n".into(), false),
            ("one\ntwo\n".into(), false),
            ("one\ntwo\nthree\n".into(), true),
        ];
    }
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Running),
    )
    .await
    .unwrap();
    let mut rx = e.state.tx.subscribe();

    poll_once(&e.state).await;
    poll_once(&e.state).await;

    let mut chunks = Vec::new();
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let WsMessage::ApplyLog(c) = rx.recv().await.unwrap() {
                let eof = c.eof;
                chunks.push(c);
                if eof {
                    break;
                }
            }
        }
    })
    .await
    .expect("log reached eof");
    let got: Vec<(u64, &str, bool)> = chunks
        .iter()
        .map(|c| (c.offset, c.data.as_str(), c.eof))
        .collect();
    assert_eq!(
        got,
        vec![
            (0, "one\n", false),
            (4, "two\n", false),
            (8, "three\n", true)
        ]
    );
    assert!(chunks.iter().all(|c| c.apply_id == "a1"));

    let stored = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let row = db::get_apply(&e.state.db, "a1").await.unwrap().unwrap();
            if let Some(log) = row.log {
                return log;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("log stored");
    assert_eq!(stored, "one\ntwo\nthree\n");
    // One follower only: exactly one read per scripted state.
    assert_eq!(fake.lock().unwrap().log_hits, 3);
}

#[tokio::test]
async fn unreachable_agent_logged_once_per_change() {
    // Nothing listens on this port once the listener is dropped.
    let closed = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let closed_addr = closed.local_addr().unwrap();
    drop(closed);
    let e = env(closed_addr, None).await;
    let mut lines = Vec::new();
    for _ in 0..3 {
        lines.extend(poll_once(&e.state).await);
    }
    assert_eq!(lines.len(), 1, "{lines:?}");
    assert!(lines[0].starts_with("H1: agent unreachable: "), "{lines:?}");
}

#[tokio::test]
async fn agent_recovery_logged_once() {
    let fake = Shared::default();
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    let mut lines = Vec::new();
    for _ in 0..2 {
        lines.extend(poll_once(&e.state).await);
    }
    fake.lock().unwrap().status = Some(agent_status(OLD, None));
    for _ in 0..2 {
        lines.extend(poll_once(&e.state).await);
    }
    assert_eq!(lines.len(), 2, "{lines:?}");
    assert!(lines[0].starts_with("H1: agent unreachable: "), "{lines:?}");
    assert_eq!(lines[1], "H1: agent reachable again");
}

#[tokio::test]
async fn follow_log_continues_at_next_after_invalid_utf8() {
    let fake = Shared::default();
    {
        let mut f = fake.lock().unwrap();
        f.status = Some(agent_status(
            OLD,
            Some(record("a1", NEW, ApplyState::Running)),
        ));
        // An invalid byte mid-chunk: the text gets U+FFFD (3 bytes) for 1 raw byte.
        f.log_script = vec![
            (b"a\xffb\n".to_vec(), false),
            (b"a\xffb\nmore\n".to_vec(), true),
        ];
    }
    let addr = fake_agent(fake.clone()).await;
    let e = env(addr, None).await;
    db::insert_apply(
        &e.state.db,
        "H1",
        "alice",
        1,
        &record("a1", NEW, ApplyState::Running),
    )
    .await
    .unwrap();
    let mut rx = e.state.tx.subscribe();

    poll_once(&e.state).await;

    let mut chunks = Vec::new();
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let WsMessage::ApplyLog(c) = rx.recv().await.unwrap() {
                let eof = c.eof;
                chunks.push(c);
                if eof {
                    break;
                }
            }
        }
    })
    .await
    .expect("log reached eof");
    let got: Vec<(u64, &str, u64, bool)> = chunks
        .iter()
        .map(|c| (c.offset, c.data.as_str(), c.next, c.eof))
        .collect();
    assert_eq!(
        got,
        vec![(0, "a\u{fffd}b\n", 4, false), (4, "more\n", 9, true)]
    );
    let stored = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let row = db::get_apply(&e.state.db, "a1").await.unwrap().unwrap();
            if let Some(log) = row.log {
                return log;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("log stored");
    assert_eq!(stored, "a\u{fffd}b\nmore\n");
    assert_eq!(fake.lock().unwrap().log_offsets, vec![0, 4]);
}
