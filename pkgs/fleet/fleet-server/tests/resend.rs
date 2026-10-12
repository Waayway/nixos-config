use fleet_proto::{AgentStatus, ApplyRecord, ApplyState, CheckoutStatus};
use fleet_server::resend::should_resend;

const OLD: &str = "0000000000000000000000000000000000000000";
const NEW: &str = "1111111111111111111111111111111111111111";

fn status(running: &str, apply: Option<(&str, ApplyState)>) -> AgentStatus {
    AgentStatus {
        host: "h".into(),
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
        apply: apply.map(|(id, state)| ApplyRecord {
            apply_id: id.into(),
            commit: NEW.into(),
            state,
            skip_reason: None,
            message: None,
            exit_code: None,
            started_at: None,
            finished_at: None,
        }),
    }
}

#[test]
fn never_received() {
    assert!(should_resend(Some("a1"), Some(NEW), &status(OLD, None)));
}

#[test]
fn same_id_failed() {
    let s = status(OLD, Some(("a1", ApplyState::Failed)));
    assert!(!should_resend(Some("a1"), Some(NEW), &s));
}

#[test]
fn same_id_skipped() {
    let s = status(OLD, Some(("a1", ApplyState::Skipped)));
    assert!(!should_resend(Some("a1"), Some(NEW), &s));
}

#[test]
fn other_id_running() {
    let s = status(OLD, Some(("a0", ApplyState::Running)));
    assert!(!should_resend(Some("a1"), Some(NEW), &s));
}

#[test]
fn other_id_finished_still_behind() {
    for state in [ApplyState::Ok, ApplyState::Failed, ApplyState::Skipped] {
        let s = status(OLD, Some(("a0", state)));
        assert!(should_resend(Some("a1"), Some(NEW), &s));
    }
}

#[test]
fn running_desired_commit() {
    assert!(!should_resend(Some("a1"), Some(NEW), &status(NEW, None)));
}

#[test]
fn running_desired_commit_dirty() {
    let s = status(&format!("{NEW}-dirty"), Some(("a0", ApplyState::Ok)));
    assert!(!should_resend(Some("a1"), Some(NEW), &s));
}

#[test]
fn no_desired() {
    assert!(!should_resend(None, None, &status(OLD, None)));
}
