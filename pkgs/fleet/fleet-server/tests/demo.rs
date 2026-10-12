//! Demo mode: the real server against a simulated fleet, run at 20x speed.

use std::time::{Duration, Instant};

use fleet_proto::{ApplyState, HostView, OnlineState, SkipReason, Snapshot};
use fleet_server::demo::{self, DemoHandle};
use serde_json::{Value, json};

const SPEED: f64 = 20.0;

async fn start() -> DemoHandle {
    demo::start("127.0.0.1:0".parse().unwrap(), SPEED)
        .await
        .unwrap()
}

async fn snapshot(d: &DemoHandle) -> Snapshot {
    reqwest::get(format!("http://{}/api/snapshot", d.addr))
        .await
        .unwrap()
        .json()
        .await
        .unwrap()
}

fn host<'a>(s: &'a Snapshot, name: &str) -> &'a HostView {
    s.hosts.iter().find(|h| h.name == name).unwrap()
}

fn head(s: &Snapshot, channel: &str) -> Option<String> {
    s.channels
        .iter()
        .find(|c| c.name == channel)
        .and_then(|c| c.head.clone())
}

/// Polls the snapshot until `pred` holds, or panics with the last snapshot after `secs`.
async fn wait_for(
    d: &DemoHandle,
    secs: u64,
    what: &str,
    pred: impl Fn(&Snapshot) -> bool,
) -> Snapshot {
    let deadline = Instant::now() + Duration::from_secs(secs);
    loop {
        let s = snapshot(d).await;
        if pred(&s) {
            return s;
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for {what}: {s:#?}");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

async fn post(d: &DemoHandle, path: &str, body: Value) -> (u16, Value) {
    let resp = reqwest::Client::new()
        .post(format!("http://{}{path}", d.addr))
        .json(&body)
        .send()
        .await
        .unwrap();
    let code = resp.status().as_u16();
    (code, resp.json().await.unwrap())
}

async fn apply(d: &DemoHandle, name: &str) -> Value {
    let (code, body) = post(d, &format!("/api/hosts/{name}/apply"), json!({})).await;
    assert_eq!(code, 202, "{body}");
    body
}

fn last_state(s: &Snapshot, name: &str) -> Option<ApplyState> {
    host(s, name).last_apply.as_ref().map(|a| a.state.clone())
}

/// Waits until the host's agent has been polled at least once.
async fn wait_polled(d: &DemoHandle, name: &str) {
    wait_for(d, 10, &format!("{name} polled"), |s| {
        host(s, name).online == OnlineState::On
    })
    .await;
}

#[tokio::test]
async fn demo_starts_and_serves_snapshot() {
    let d = start().await;
    let s = wait_for(&d, 10, "atlas checkout", |s| {
        host(s, "atlas").checkout.is_some()
    })
    .await;
    assert!(s.demo);
    assert_eq!(s.hosts.len(), 7);
    let mut names: Vec<_> = s.channels.iter().map(|c| c.name.as_str()).collect();
    names.sort();
    assert_eq!(names, ["stable", "unstable"]);
    assert!(head(&s, "unstable").is_some());
    assert!(head(&s, "stable").is_some());
    assert!(host(&s, "atlas").checkout.as_ref().unwrap().dirty);
}

#[tokio::test]
async fn demo_apply_hermes_reaches_ok() {
    let d = start().await;
    wait_polled(&d, "hermes").await;
    apply(&d, "hermes").await;
    let s = wait_for(&d, 10, "hermes ok", |s| {
        last_state(s, "hermes") == Some(ApplyState::Ok)
    })
    .await;
    let h = host(&s, "hermes");
    assert_eq!(h.running, head(&s, "unstable"));
    assert_eq!(h.behind, Some(0));
}

#[tokio::test]
async fn demo_apply_atlas_skips_dirty() {
    let d = start().await;
    wait_polled(&d, "atlas").await;
    apply(&d, "atlas").await;
    let s = wait_for(&d, 10, "atlas skipped", |s| {
        last_state(s, "atlas") == Some(ApplyState::Skipped)
    })
    .await;
    let a = host(&s, "atlas").last_apply.clone().unwrap();
    assert_eq!(a.skip_reason, Some(SkipReason::Dirty));
}

#[tokio::test]
async fn demo_media_first_apply_fails() {
    let d = start().await;
    wait_polled(&d, "media").await;
    apply(&d, "media").await;
    let s = wait_for(&d, 10, "media failed", |s| {
        last_state(s, "media") == Some(ApplyState::Failed)
    })
    .await;
    let a = host(&s, "media").last_apply.clone().unwrap();
    assert!(a.exit_code.is_some_and(|c| c != 0), "{a:?}");
}

#[tokio::test]
async fn demo_apollo_resend_after_online() {
    let d = start().await;
    let s = snapshot(&d).await;
    assert_eq!(host(&s, "apollo").online, OnlineState::Off);
    let body = apply(&d, "apollo").await;
    assert_eq!(body["agent_status"], "unreachable", "{body}");
    let s = wait_for(&d, 20, "apollo ok", |s| {
        last_state(s, "apollo") == Some(ApplyState::Ok)
    })
    .await;
    let a = host(&s, "apollo").last_apply.clone().unwrap();
    assert_eq!(
        Some(a.apply_id),
        body["apply_id"].as_str().map(String::from)
    );
    assert_eq!(host(&s, "apollo").running, Some(a.commit));
}

#[tokio::test]
async fn demo_promote_moves_stable() {
    let d = start().await;
    let s = snapshot(&d).await;
    let candidate = s.promote_candidate.clone().expect("promote candidate");
    let (code, body) = post(&d, "/api/promote", json!({ "commit": candidate })).await;
    assert_eq!(code, 200, "{body}");
    let s = snapshot(&d).await;
    assert_eq!(head(&s, "stable"), Some(candidate));
}
