//! The dashboard HTTP API, WebSocket and embedded frontend, served on 127.0.0.1:0
//! against a fake agent and a local bare repo.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use fleet_proto::{ApplyRequest, AuditEvent, LogChunk, WsMessage};
use fleet_server::config::{AccessConfig, FleetHost, OnlineSource, ServerConfig};
use fleet_server::db;
use fleet_server::db::entities::applies;
use fleet_server::mirror::Mirror;
use fleet_server::state::AppState;
use fleet_server::tailscale::StaticOnline;
use futures::StreamExt;
use sea_orm::EntityTrait;
use serde::Deserialize;
use serde_json::{Value, json};

/// A client that sends the header the dashboard sends (`X-Fleet: 1`, CSRF guard).
fn dashboard_client() -> reqwest::Client {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert("x-fleet", reqwest::header::HeaderValue::from_static("1"));
    reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .unwrap()
}

fn git(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .current_dir(dir)
        .args(args)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_AUTHOR_NAME", "t")
        .env("GIT_AUTHOR_EMAIL", "t@example.com")
        .env("GIT_COMMITTER_NAME", "t")
        .env("GIT_COMMITTER_EMAIL", "t@example.com")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap().trim().to_string()
}

/// A bare "origin" plus a working clone used to create commits on it.
struct Origin {
    bare: PathBuf,
    work: PathBuf,
}

impl Origin {
    fn new(dir: &Path) -> Origin {
        let bare = dir.join("origin.git");
        let work = dir.join("work");
        std::fs::create_dir_all(&work).unwrap();
        git(
            dir,
            &["init", "--bare", "-b", "main", bare.to_str().unwrap()],
        );
        git(&work, &["init", "-b", "unstable"]);
        git(&work, &["remote", "add", "origin", bare.to_str().unwrap()]);
        Origin { bare, work }
    }

    /// Commit on the current branch and push it; returns the new hash.
    fn commit(&self, subject: &str, push_branch: &str) -> String {
        git(&self.work, &["commit", "--allow-empty", "-m", subject]);
        let h = git(&self.work, &["rev-parse", "HEAD"]);
        self.push(push_branch);
        h
    }

    fn push(&self, branch: &str) {
        git(
            &self.work,
            &["push", "-f", "origin", &format!("HEAD:refs/heads/{branch}")],
        );
    }

    fn bare_ref(&self, branch: &str) -> String {
        git(&self.bare, &["rev-parse", &format!("refs/heads/{branch}")])
    }
}

#[derive(Default)]
struct Fake {
    applied: Vec<ApplyRequest>,
}

type Shared = Arc<Mutex<Fake>>;

#[derive(Deserialize)]
struct LogQ {
    apply_id: String,
    offset: u64,
}

async fn fake_agent(fake: Shared) -> SocketAddr {
    async fn apply(State(f): State<Shared>, Json(req): Json<ApplyRequest>) -> StatusCode {
        f.lock().unwrap().applied.push(req);
        StatusCode::ACCEPTED
    }
    async fn log(Query(q): Query<LogQ>) -> Json<LogChunk> {
        Json(LogChunk {
            apply_id: q.apply_id,
            offset: q.offset,
            data: "live log\n".into(),
            next: q.offset + 9,
            eof: false,
        })
    }
    let app = Router::new()
        .route("/apply", post(apply))
        .route("/apply/log", get(log))
        .with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    addr
}

fn host(name: &str, channel: &str) -> FleetHost {
    FleetHost {
        name: name.into(),
        system: "x86_64-linux".into(),
        user: "u".into(),
        channel: channel.into(),
        os: "nixos".into(),
    }
}

struct Env {
    state: AppState,
    base: String,
    _dir: tempfile::TempDir,
}

/// Starts the dashboard server without access control. Every host is online at `agent`.
async fn env(dir: tempfile::TempDir, repo: &str, agent: SocketAddr, hosts: Vec<FleetHost>) -> Env {
    env_with_access(dir, repo, agent, hosts, AccessConfig::Disabled).await
}

async fn env_with_access(
    dir: tempfile::TempDir,
    repo: &str,
    agent: SocketAddr,
    hosts: Vec<FleetHost>,
    access: AccessConfig,
) -> Env {
    let addresses: HashMap<String, String> = hosts
        .iter()
        .map(|h| (h.name.to_lowercase(), agent.to_string()))
        .collect();
    let cfg = ServerConfig {
        listen: "127.0.0.1:0".parse().unwrap(),
        agent_port: 7461,
        hosts_file: dir.path().join("hosts.json"),
        repo_url: repo.into(),
        push_url: repo.into(),
        deploy_key_file: None,
        state_dir: dir.path().join("state"),
        access,
        online: OnlineSource::Static {
            addresses: addresses.clone(),
        },
        mirror_fetch_secs: 300,
        poll_secs: 60,
        tailscale_bin: PathBuf::from("tailscale"),
    };
    let conn = db::connect(&cfg.state_dir).await.unwrap();
    let mirror = Arc::new(Mirror::open_or_init(&cfg).await.unwrap());
    let online = Arc::new(StaticOnline::new(&addresses).unwrap());
    let state = AppState::new(Arc::new(cfg), conn, mirror, online, hosts).unwrap();
    let app = fleet_server::api::app(state.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .unwrap()
    });
    Env {
        state,
        base: format!("http://{addr}"),
        _dir: dir,
    }
}

fn audit_kinds(events: &[AuditEvent], kind: &str) -> Vec<AuditEvent> {
    events.iter().filter(|e| e.kind == kind).cloned().collect()
}

#[tokio::test]
async fn apply_endpoint_creates_desired_and_hits_agent() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    let head = o.commit("one", "main");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    let e = env(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
    )
    .await;
    let mut rx = e.state.tx.subscribe();
    let http = dashboard_client();

    let resp = http
        .post(format!("{}/api/hosts/H1/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);
    let body: Value = resp.json().await.unwrap();
    assert_eq!(body["agent_status"], "202", "{body}");
    let id = body["apply_id"].as_str().unwrap().to_string();
    assert_eq!(id.len(), 36, "{id}");

    let desired = db::desired(&e.state.db, "H1").await.unwrap().unwrap();
    assert_eq!(desired.apply_id, id);
    assert_eq!(desired.commit, head);
    assert_eq!(desired.requested_by, "dev");
    assert_eq!(desired.state, "idle");
    assert_eq!(
        fake.lock().unwrap().applied,
        vec![ApplyRequest {
            apply_id: id.clone(),
            commit: head.clone()
        }]
    );
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    let requested = audit_kinds(&audit, "apply_requested");
    assert_eq!(requested.len(), 1, "{audit:?}");
    assert_eq!(requested[0].actor, "dev");
    assert_eq!(requested[0].host.as_deref(), Some("H1"));
    match rx.recv().await.unwrap() {
        WsMessage::HostUpdated(hv) => assert_eq!(hv.desired_apply_id.as_deref(), Some(&*id)),
        other => panic!("unexpected {other:?}"),
    }

    // Unknown host: 404.
    let resp = http
        .post(format!("{}/api/hosts/nope/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // No stored log yet: the live log comes from the agent.
    let log = http
        .get(format!("{}/api/hosts/H1/applies/{id}/log", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(log.status(), StatusCode::OK);
    assert_eq!(log.text().await.unwrap(), "live log\n");
    db::set_apply_log(&e.state.db, &id, "stored log\n")
        .await
        .unwrap();
    let log = http
        .get(format!("{}/api/hosts/H1/applies/{id}/log", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(log.text().await.unwrap(), "stored log\n");

    let audit: Vec<AuditEvent> = http
        .get(format!("{}/api/audit?limit=100", e.base))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(audit_kinds(&audit, "apply_requested").len(), 1);
}

#[tokio::test]
async fn state_changing_requests_need_the_dashboard_header() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("one", "main");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    let e = env(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
    )
    .await;
    let bare = reqwest::Client::new();
    let url = format!("{}/api/hosts/H1/apply", e.base);

    // No header (a cross-site form or no-cors fetch): refused, nothing applied.
    let resp = bare.post(&url).send().await.unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    let body: Value = resp.json().await.unwrap();
    assert!(body["error"].is_string(), "{body}");
    let resp = bare
        .post(format!("{}/api/channels/main/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    let resp = bare
        .post(format!("{}/api/promote", e.base))
        .json(&json!({"commit": "0".repeat(40)}))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // The header, but the browser says the request is cross-site: refused.
    for site in ["cross-site", "same-site"] {
        let resp = bare
            .post(&url)
            .header("x-fleet", "1")
            .header("sec-fetch-site", site)
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN, "{site}");
    }
    assert!(fake.lock().unwrap().applied.is_empty());
    assert!(
        applies::Entity::find()
            .all(&e.state.db)
            .await
            .unwrap()
            .is_empty()
    );

    // GETs need no header.
    let resp = bare
        .get(format!("{}/api/snapshot", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // The header from the dashboard's own origin (or without Sec-Fetch-Site): accepted.
    let resp = bare
        .post(&url)
        .header("x-fleet", "1")
        .header("sec-fetch-site", "same-origin")
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);
    let resp = bare.post(&url).header("x-fleet", "1").send().await.unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);
    assert_eq!(fake.lock().unwrap().applied.len(), 2);
}

#[tokio::test]
async fn apply_endpoint_502_when_mirror_fetch_fails() {
    let dir = tempfile::tempdir().unwrap();
    let bogus = dir.path().join("does-not-exist.git");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    let e = env(
        dir,
        bogus.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
    )
    .await;

    let resp = dashboard_client()
        .post(format!("{}/api/hosts/H1/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_GATEWAY);
    let body: Value = resp.json().await.unwrap();
    assert!(body["error"].is_string(), "{body}");
    assert!(
        applies::Entity::find()
            .all(&e.state.db)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(db::desired(&e.state.db, "H1").await.unwrap().is_none());
    assert!(fake.lock().unwrap().applied.is_empty());
}

#[tokio::test]
async fn channel_apply_targets_only_that_channel() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("stable one", "stable");
    let head = o.commit("main two", "main");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    let hosts = vec![host("H1", "main"), host("H2", "stable"), host("H3", "main")];
    let e = env(dir, o.bare.to_str().unwrap(), agent, hosts).await;
    let http = dashboard_client();

    let resp = http
        .post(format!("{}/api/channels/main/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);
    let body: Value = resp.json().await.unwrap();
    let ids = body["apply_ids"].as_object().unwrap();
    let mut names: Vec<&str> = ids.keys().map(String::as_str).collect();
    names.sort();
    assert_eq!(names, ["H1", "H3"]);
    for name in ["H1", "H3"] {
        let d = db::desired(&e.state.db, name).await.unwrap().unwrap();
        assert_eq!(d.apply_id, ids[name].as_str().unwrap());
        assert_eq!(d.commit, head);
    }
    assert!(db::desired(&e.state.db, "H2").await.unwrap().is_none());
    let applied = fake.lock().unwrap().applied.clone();
    assert_eq!(applied.len(), 2);
    assert!(applied.iter().all(|r| r.commit == head));
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    assert_eq!(audit_kinds(&audit, "apply_requested").len(), 2);

    let resp = http
        .post(format!("{}/api/channels/nope/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn promote_moves_stable_and_audits() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    let c1 = o.commit("one", "stable");
    o.push("unstable");
    let c2 = o.commit("two", "unstable");
    git(&o.work, &["checkout", "-q", "-b", "side", &c1]);
    let side = o.commit("side", "side");
    let fake = Shared::default();
    let agent = fake_agent(fake).await;
    let e = env(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "stable")],
    )
    .await;
    let mut rx = e.state.tx.subscribe();
    let http = dashboard_client();
    let promote = |body: Value| {
        let (http, url) = (http.clone(), format!("{}/api/promote", e.base));
        async move { http.post(url).json(&body).send().await.unwrap() }
    };

    assert_eq!(
        promote(json!({"commit": "--delete"})).await.status(),
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        promote(json!({"commit": side})).await.status(),
        StatusCode::CONFLICT
    );
    assert_eq!(o.bare_ref("stable"), c1);

    let resp = promote(json!({"commit": c2})).await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(o.bare_ref("stable"), c2);
    let audit = db::recent_audit(&e.state.db, 100).await.unwrap();
    let promotes = audit_kinds(&audit, "promote");
    assert_eq!(promotes.len(), 1, "{audit:?}");
    assert_eq!(promotes[0].actor, "dev");
    assert_eq!(promotes[0].details["commit"], c2);
    match rx.recv().await.unwrap() {
        WsMessage::ChannelsUpdated(chs) => {
            let stable = chs.iter().find(|c| c.name == "stable").unwrap();
            assert_eq!(stable.head.as_deref(), Some(&*c2));
        }
        other => panic!("unexpected {other:?}"),
    }
}

#[tokio::test]
async fn ws_sends_snapshot_first() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("one", "main");
    let agent = fake_agent(Shared::default()).await;
    let e = env(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
    )
    .await;

    let url = format!("{}/api/ws", e.base.replacen("http", "ws", 1));
    let (mut ws, _) = tokio_tungstenite::connect_async(url).await.unwrap();
    let first = ws.next().await.unwrap().unwrap();
    let msg: WsMessage = serde_json::from_str(first.to_text().unwrap()).unwrap();
    match msg {
        WsMessage::Snapshot(s) => {
            assert_eq!(s.viewer, "dev");
            assert_eq!(s.hosts.len(), 1);
            assert_eq!(s.hosts[0].name, "H1");
        }
        other => panic!("unexpected {other:?}"),
    }

    // Broadcasts are forwarded after the snapshot.
    let chs = fleet_server::state::channels(&e.state).await;
    e.state.broadcast(WsMessage::ChannelsUpdated(chs.clone()));
    let next = ws.next().await.unwrap().unwrap();
    let msg: WsMessage = serde_json::from_str(next.to_text().unwrap()).unwrap();
    assert_eq!(msg, WsMessage::ChannelsUpdated(chs));
    ws.close(None).await.unwrap();
}

#[tokio::test]
async fn spa_fallback_serves_index() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("one", "main");
    let agent = fake_agent(Shared::default()).await;
    let e = env(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
    )
    .await;
    let http = dashboard_client();

    for path in ["/", "/index.html", "/hosts/H1"] {
        let resp = http.get(format!("{}{path}", e.base)).send().await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK, "{path}");
        let ct = resp.headers()["content-type"].to_str().unwrap().to_string();
        assert!(ct.starts_with("text/html"), "{path}: {ct}");
        assert!(resp.text().await.unwrap().contains(r#"id="app""#), "{path}");
    }
    // Unknown API routes are not swallowed by the SPA fallback.
    let resp = http
        .get(format!("{}/api/nope", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    let snap: fleet_proto::Snapshot = http
        .get(format!("{}/api/snapshot", e.base))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(snap.viewer, "dev");
}

#[tokio::test]
async fn access_denied_on_api_ws_and_static() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("one", "main");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    // StaticOnline has no whois identities, so Tailscale access control denies everyone.
    let access = AccessConfig::Tailscale {
        allowed_users: vec!["Waayway@github".into()],
        allowed_tags: vec!["tag:fleet".into()],
    };
    let e = env_with_access(
        dir,
        o.bare.to_str().unwrap(),
        agent,
        vec![host("H1", "main")],
        access,
    )
    .await;
    let http = dashboard_client();

    for path in [
        "/",
        "/index.html",
        "/hosts/H1",
        "/api/snapshot",
        "/api/audit",
    ] {
        let resp = http.get(format!("{}{path}", e.base)).send().await.unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN, "{path}");
    }
    let resp = http
        .post(format!("{}/api/hosts/H1/apply", e.base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    assert!(fake.lock().unwrap().applied.is_empty());

    let url = format!("{}/api/ws", e.base.replacen("http", "ws", 1));
    match tokio_tungstenite::connect_async(url).await {
        Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
            assert_eq!(resp.status(), StatusCode::FORBIDDEN)
        }
        other => panic!("expected 403 on upgrade, got {other:?}"),
    }
}

#[tokio::test]
async fn concurrent_applies_all_accepted() {
    let dir = tempfile::tempdir().unwrap();
    let o = Origin::new(dir.path());
    o.commit("one", "main");
    let fake = Shared::default();
    let agent = fake_agent(fake.clone()).await;
    let names: Vec<String> = (1..=8).map(|i| format!("H{i}")).collect();
    let hosts = names.iter().map(|n| host(n, "main")).collect();
    let e = env(dir, o.bare.to_str().unwrap(), agent, hosts).await;
    // A push right before the presses, so every fetch has refs to write.
    let head = o.commit("two", "main");
    let http = dashboard_client();

    let presses = names.iter().map(|n| {
        let (http, url) = (http.clone(), format!("{}/api/hosts/{n}/apply", e.base));
        async move { http.post(url).send().await.unwrap().status() }
    });
    // The background fetch runs at the same time.
    let background = async {
        for _ in 0..4 {
            e.state.mirror.fetch().await.unwrap();
        }
    };
    let (statuses, ()) = tokio::join!(futures::future::join_all(presses), background);
    assert!(
        statuses.iter().all(|s| *s == StatusCode::ACCEPTED),
        "{statuses:?}"
    );
    for n in &names {
        let d = db::desired(&e.state.db, n).await.unwrap().unwrap();
        assert_eq!(d.commit, head, "{n}");
    }
    assert_eq!(fake.lock().unwrap().applied.len(), names.len());
}
