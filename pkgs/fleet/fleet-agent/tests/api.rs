mod common;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use axum::Router;
use axum::body::{Body, to_bytes};
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Method, Request, StatusCode};
use common::*;
use fleet_agent::activations::read_since;
use fleet_agent::api::{AppState, router};
use fleet_agent::net::{SourceGuard, is_tailscale};
use fleet_proto::{ActivationsResponse, AgentStatus, ApplyState};
use tower::ServiceExt;

const MANAGER: &str = "127.0.0.1:50000";

fn app(f: &Fixture, from: &str) -> Router {
    let config_path = f.cfg.state_dir.parent().unwrap().join("config.json");
    std::fs::write(&config_path, serde_json::to_vec(&f.cfg).unwrap()).unwrap();
    let state = AppState::new(
        f.cfg.clone(),
        config_path,
        SourceGuard::new("127.0.0.1".into()),
    )
    .unwrap();
    router(state).layer(MockConnectInfo(from.parse::<SocketAddr>().unwrap()))
}

fn configured() -> Fixture {
    let mut f = fixture();
    f.cfg.agent_exe = Some(PathBuf::from(env!("CARGO_BIN_EXE_fleet-agent")));
    f.cfg.revision_command = Some(vec!["sh".into(), "-c".into(), "echo rev1".into()]);
    f.cfg.rebuild_command = Some(vec!["sh".into(), "-c".into(), "exit 0".into()]);
    f
}

async fn call(
    app: &Router,
    method: Method,
    uri: &str,
    body: Option<String>,
) -> (StatusCode, Vec<u8>) {
    let req = Request::builder()
        .method(method)
        .uri(uri)
        .header("content-type", "application/json")
        .body(body.map(Body::from).unwrap_or_else(Body::empty))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let status = resp.status();
    (
        status,
        to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap()
            .to_vec(),
    )
}

fn apply_body(id: &str, commit: &str) -> Option<String> {
    Some(format!(r#"{{"apply_id":"{id}","commit":"{commit}"}}"#))
}

async fn status(app: &Router) -> AgentStatus {
    let (code, body) = call(app, Method::GET, "/status", None).await;
    assert_eq!(code, StatusCode::OK);
    serde_json::from_slice(&body).unwrap()
}

async fn wait_state(app: &Router, want: ApplyState) -> AgentStatus {
    let end = Instant::now() + Duration::from_secs(30);
    loop {
        let s = status(app).await;
        if s.apply.as_ref().is_some_and(|a| a.state == want) {
            return s;
        }
        assert!(
            Instant::now() < end,
            "timed out waiting for {want:?}: {s:?}"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

#[tokio::test]
async fn rejects_foreign_source() {
    let f = configured();
    let app = app(&f, "10.9.9.9:1234");
    let (code, _) = call(&app, Method::GET, "/status", None).await;
    assert_eq!(code, StatusCode::FORBIDDEN);
    let (code, _) = call(
        &app,
        Method::POST,
        "/apply",
        apply_body("a1", &"0".repeat(40)),
    )
    .await;
    assert_eq!(code, StatusCode::FORBIDDEN);
    let (code, _) = call(&app, Method::GET, "/activations?since=0", None).await;
    assert_eq!(code, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn bad_commit_400() {
    let f = configured();
    let app = app(&f, MANAGER);
    for commit in ["abc", &"A".repeat(40), &"g".repeat(40)] {
        let (code, _) = call(&app, Method::POST, "/apply", apply_body("a1", commit)).await;
        assert_eq!(code, StatusCode::BAD_REQUEST, "{commit}");
    }
    let (code, _) = call(
        &app,
        Method::POST,
        "/apply",
        apply_body("../x", &"0".repeat(40)),
    )
    .await;
    assert_eq!(code, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn apply_202_then_status_ok() {
    let f = configured();
    let c = push_remote_commit(&f, "b.txt");
    fleet_agent::git::Git::new(&f.cfg)
        .unwrap()
        .fetch(&f.cfg.repo_url)
        .unwrap();
    let app = app(&f, MANAGER);
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::ACCEPTED);
    let s = wait_state(&app, ApplyState::Ok).await;
    assert_eq!(s.running, "rev1");
    assert_eq!(s.host, "h");
    assert_eq!(s.checkout.head.as_deref(), Some(c.as_str()));
    assert_eq!(s.checkout.branch.as_deref(), Some("unstable"));
    assert_eq!(s.checkout.ahead, Some(0));
    let (code, body) = call(&app, Method::GET, "/apply/log?apply_id=id-1", None).await;
    assert_eq!(code, StatusCode::OK);
    let log: fleet_proto::LogChunk = serde_json::from_slice(&body).unwrap();
    assert!(log.eof);
    let (code, _) = call(&app, Method::GET, "/apply/log?apply_id=nope&offset=0", None).await;
    assert_eq!(code, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn duplicate_apply_id_200() {
    let f = configured();
    let c = push_remote_commit(&f, "b.txt");
    fleet_agent::git::Git::new(&f.cfg)
        .unwrap()
        .fetch(&f.cfg.repo_url)
        .unwrap();
    let app = app(&f, MANAGER);
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::ACCEPTED);
    wait_state(&app, ApplyState::Ok).await;
    let (code, body) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::OK);
    let rec: fleet_proto::ApplyRecord = serde_json::from_slice(&body).unwrap();
    assert_eq!(rec.apply_id, "id-1");
    assert_eq!(rec.state, ApplyState::Ok);
}

#[tokio::test]
async fn apply_while_running_409() {
    let mut f = configured();
    f.cfg.rebuild_command = Some(vec!["sh".into(), "-c".into(), "sleep 2".into()]);
    let c = push_remote_commit(&f, "b.txt");
    fleet_agent::git::Git::new(&f.cfg)
        .unwrap()
        .fetch(&f.cfg.repo_url)
        .unwrap();
    let app = app(&f, MANAGER);
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::ACCEPTED);
    wait_state(&app, ApplyState::Running).await;
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-2", &c)).await;
    assert_eq!(code, StatusCode::CONFLICT);
    wait_state(&app, ApplyState::Ok).await;
}

#[tokio::test]
async fn body_over_4k_rejected() {
    let f = configured();
    let app = app(&f, MANAGER);
    let big = format!(r#"{{"apply_id":"{}","commit":"x"}}"#, "a".repeat(5000));
    let (code, _) = call(&app, Method::POST, "/apply", Some(big)).await;
    assert_eq!(code, StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn activations_since_skips_partial_line() {
    let f = configured();
    std::fs::create_dir_all(&f.cfg.state_dir).unwrap();
    let path = f.cfg.state_dir.join("activations.jsonl");
    let l = |t: i64, trig: &str| {
        format!(
            r#"{{"time":{t},"store_path":"/nix/store/x","revision":"r{t}","generation":{t},"trigger":"{trig}","sudo_user":null}}"#
        )
    };
    let content = format!(
        "{}\nnot json\n{}\n{{\"time\":3,\"sto",
        l(1, "boot"),
        l(2, "manual")
    );
    std::fs::write(&path, content).unwrap();

    let all = read_since(&path, 0);
    assert_eq!(all.next, 3);
    assert_eq!(all.events.len(), 2);
    assert_eq!(all.events[0].line, 0);
    assert_eq!(all.events[1].line, 2);
    assert_eq!(all.events[1].trigger, "manual");

    let rest = read_since(&path, 1);
    assert_eq!(rest.next, 3);
    assert_eq!(rest.events.len(), 1);

    // Once the partial line is completed it shows up with its own line number.
    let mut s = std::fs::read_to_string(&path).unwrap();
    s.truncate(s.rfind("{\"time\":3").unwrap());
    s.push_str(&format!("{}\n", l(3, "apply:x")));
    std::fs::write(&path, s).unwrap();
    let r = read_since(&path, all.next);
    assert_eq!(r.next, 4);
    assert_eq!(r.events.len(), 1);
    assert_eq!(r.events[0].line, 3);

    let app = app(&f, MANAGER);
    let (code, body) = call(&app, Method::GET, "/activations?since=2", None).await;
    assert_eq!(code, StatusCode::OK);
    let resp: ActivationsResponse = serde_json::from_slice(&body).unwrap();
    assert_eq!(resp.next, 4);
    assert_eq!(resp.events.len(), 2);

    let missing = read_since(&f.cfg.state_dir.join("nope"), 0);
    assert!(missing.events.is_empty() && missing.next == 0);
}

#[test]
fn is_tailscale_ranges() {
    assert!(is_tailscale("100.95.164.9".parse().unwrap()));
    assert!(is_tailscale("100.64.0.1".parse().unwrap()));
    assert!(is_tailscale("100.127.255.255".parse().unwrap()));
    assert!(!is_tailscale("100.128.0.1".parse().unwrap()));
    assert!(!is_tailscale("100.63.0.1".parse().unwrap()));
    assert!(is_tailscale("fd7a:115c:a1e0::1".parse().unwrap()));
    assert!(!is_tailscale("fd7a:115c:a1e1::1".parse().unwrap()));
    assert!(!is_tailscale("10.0.0.1".parse().unwrap()));
}

#[tokio::test]
async fn back_to_back_applies_second_is_409() {
    let mut f = configured();
    f.cfg.rebuild_command = Some(vec!["sh".into(), "-c".into(), "sleep 1".into()]);
    let c = push_remote_commit(&f, "b.txt");
    fleet_agent::git::Git::new(&f.cfg)
        .unwrap()
        .fetch(&f.cfg.repo_url)
        .unwrap();
    let app = app(&f, MANAGER);
    let (c1, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    let (c2, _) = call(&app, Method::POST, "/apply", apply_body("id-2", &c)).await;
    let (c3, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(
        (c1, c2, c3),
        (
            StatusCode::ACCEPTED,
            StatusCode::CONFLICT,
            StatusCode::ACCEPTED
        )
    );
    wait_state(&app, ApplyState::Ok).await;
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::OK);
}

#[test]
fn second_run_apply_exits_while_lock_held() {
    let f = configured();
    let lock = fleet_agent::apply::try_lock_apply(&f.cfg).unwrap();
    let rec = fleet_agent::apply::run_apply(&f.cfg, "id-9", &"0".repeat(40));
    assert_eq!(rec.state, ApplyState::Failed);
    assert_eq!(rec.message.as_deref(), Some("another apply is running"));
    assert!(fleet_agent::apply::read_record(&f.cfg, "id-9").is_none());
    assert!(!f.cfg.state_dir.join("apply-in-progress.json").exists());
    drop(lock);
    // A concurrently forking test thread can briefly inherit the descriptor
    // (O_CLOEXEC only applies at exec), so allow a moment for it to close.
    let end = Instant::now() + Duration::from_secs(5);
    while fleet_agent::apply::try_lock_apply(&f.cfg).is_none() {
        assert!(Instant::now() < end, "lock never released");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[tokio::test]
async fn apply_records_last_fetch() {
    let f = configured();
    let c = push_remote_commit(&f, "b.txt");
    let app = app(&f, MANAGER);
    assert!(status(&app).await.checkout.last_fetch_at.is_none());
    let (code, _) = call(&app, Method::POST, "/apply", apply_body("id-1", &c)).await;
    assert_eq!(code, StatusCode::ACCEPTED);
    let s = wait_state(&app, ApplyState::Ok).await;
    assert!(s.checkout.last_fetch_at.is_some());
}
