use fleet_proto::{AgentStatus, ApplyRecord, ApplyState, CheckoutStatus, SkipReason};
use fleet_server::db;
use serde_json::json;

const C1: &str = "0123456789abcdef0123456789abcdef01234567";

fn record(id: &str, state: ApplyState) -> ApplyRecord {
    ApplyRecord {
        apply_id: id.into(),
        commit: C1.into(),
        state,
        skip_reason: None,
        message: None,
        exit_code: None,
        started_at: None,
        finished_at: None,
    }
}

#[tokio::test]
async fn migrations_run_twice_ok() {
    let dir = tempfile::tempdir().unwrap();
    db::connect(dir.path()).await.unwrap();
    let conn = db::connect(dir.path()).await.unwrap();
    assert_eq!(db::activations_next(&conn, "h").await.unwrap(), 0);
}

#[tokio::test]
async fn desired_roundtrip() {
    let dir = tempfile::tempdir().unwrap();
    let conn = db::connect(dir.path()).await.unwrap();
    assert!(db::desired(&conn, "h1").await.unwrap().is_none());
    db::insert_apply(&conn, "h1", "alice", 100, &record("a1", ApplyState::Idle))
        .await
        .unwrap();
    db::set_desired(&conn, "h1", "a1").await.unwrap();
    let d = db::desired(&conn, "h1").await.unwrap().unwrap();
    assert_eq!(
        (
            d.apply_id.as_str(),
            d.commit.as_str(),
            d.requested_by.as_str()
        ),
        ("a1", C1, "alice")
    );
    assert_eq!(d.state, "idle");

    let mut rec = record("a1", ApplyState::Skipped);
    rec.skip_reason = Some(SkipReason::Dirty);
    rec.message = Some("dirty".into());
    rec.started_at = Some(101);
    rec.finished_at = Some(102);
    db::update_apply_from_record(&conn, &rec).await.unwrap();
    db::insert_apply(&conn, "h1", "bob", 200, &record("a2", ApplyState::Idle))
        .await
        .unwrap();
    db::set_desired(&conn, "h1", "a2").await.unwrap();
    assert_eq!(
        db::desired(&conn, "h1").await.unwrap().unwrap().apply_id,
        "a2"
    );
    db::set_desired(&conn, "h1", "a1").await.unwrap();
    let d = db::desired(&conn, "h1").await.unwrap().unwrap();
    assert_eq!(d.state, "skipped");
    assert_eq!(d.skip_reason.as_deref(), Some("dirty"));
    assert_eq!(d.finished_at, Some(102));
    assert_eq!(d.requested_at, 100);
}

#[tokio::test]
async fn audit_insert_and_list_newest_first() {
    let dir = tempfile::tempdir().unwrap();
    let conn = db::connect(dir.path()).await.unwrap();
    db::insert_audit(&conn, 10, Some("h1"), "apply", "alice", json!({"n": 1}))
        .await
        .unwrap();
    db::insert_audit(&conn, 30, None, "promote", "bob", json!({"n": 2}))
        .await
        .unwrap();
    db::insert_audit(&conn, 20, Some("h2"), "apply", "carol", json!({"n": 3}))
        .await
        .unwrap();
    let ev = db::recent_audit(&conn, 2).await.unwrap();
    assert_eq!(ev.len(), 2);
    assert_eq!(
        (ev[0].time, ev[0].host.clone(), ev[0].details.clone()),
        (30, None, json!({"n": 2}))
    );
    assert_eq!(ev[1].time, 20);
}

#[tokio::test]
async fn status_roundtrip_json() {
    let dir = tempfile::tempdir().unwrap();
    let conn = db::connect(dir.path()).await.unwrap();
    assert!(db::load_status(&conn, "h1").await.unwrap().is_none());
    let st = AgentStatus {
        host: "h1".into(),
        os: "nixos".into(),
        agent_version: "0.1.0".into(),
        running: C1.into(),
        checkout: CheckoutStatus {
            branch: Some("main".into()),
            head: Some(C1.into()),
            dirty: false,
            untracked: 0,
            ahead: Some(0),
            last_fetch_at: Some(5),
        },
        apply: Some(record("a1", ApplyState::Ok)),
    };
    db::save_status(&conn, "h1", &st, 1234).await.unwrap();
    let (got, ok_at) = db::load_status(&conn, "h1").await.unwrap().unwrap();
    assert_eq!(got, st);
    assert_eq!(ok_at, Some(1234));
    db::set_activations_next(&conn, "h1", 7).await.unwrap();
    assert_eq!(db::activations_next(&conn, "h1").await.unwrap(), 7);
    // saving status must not reset the cursor
    db::save_status(&conn, "h1", &st, 1300).await.unwrap();
    assert_eq!(db::activations_next(&conn, "h1").await.unwrap(), 7);
}
