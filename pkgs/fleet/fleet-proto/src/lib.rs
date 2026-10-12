//! Shared wire types for the fleet agent, server and web frontend.
//! Times are unix seconds (`i64`).

use serde::{Deserialize, Serialize};
use ts_rs::TS;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub enum ApplyState {
    Idle,
    Running,
    Ok,
    Skipped,
    Failed,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub enum SkipReason {
    FetchFailed,
    CommitNotFound,
    CommitNotOnChannel,
    WrongBranch,
    Dirty,
    NotFastForward,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct ApplyRecord {
    pub apply_id: String,
    pub commit: String,
    pub state: ApplyState,
    pub skip_reason: Option<SkipReason>,
    pub message: Option<String>,
    pub exit_code: Option<i32>,
    #[ts(type = "number | null")]
    pub started_at: Option<i64>,
    #[ts(type = "number | null")]
    pub finished_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct CheckoutStatus {
    pub branch: Option<String>,
    pub head: Option<String>,
    pub dirty: bool,
    pub untracked: u32,
    pub ahead: Option<u32>,
    #[ts(type = "number | null")]
    pub last_fetch_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct AgentStatus {
    pub host: String,
    pub os: String,
    pub agent_version: String,
    pub running: String,
    pub checkout: CheckoutStatus,
    pub apply: Option<ApplyRecord>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct ApplyRequest {
    pub apply_id: String,
    pub commit: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct ActivationEvent {
    #[ts(type = "number")]
    pub line: u64,
    #[ts(type = "number")]
    pub time: i64,
    pub store_path: String,
    pub revision: String,
    #[ts(type = "number | null")]
    pub generation: Option<u64>,
    pub trigger: String,
    pub sudo_user: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct ActivationsResponse {
    pub events: Vec<ActivationEvent>,
    #[ts(type = "number")]
    pub next: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct LogChunk {
    pub apply_id: String,
    #[ts(type = "number")]
    pub offset: u64,
    pub data: String,
    pub eof: bool,
}

// ---- dashboard ----

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub enum OnlineState {
    Off,
    AgentUnreachable,
    On,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct HostView {
    pub name: String,
    pub os: String,
    pub channel: String,
    pub online: OnlineState,
    #[ts(type = "number | null")]
    pub last_seen: Option<i64>,
    pub running: Option<String>,
    pub running_dirty: bool,
    pub behind: Option<u32>,
    pub checkout: Option<CheckoutStatus>,
    pub last_apply: Option<ApplyRecord>,
    pub desired_apply_id: Option<String>,
    pub last_activation: Option<ActivationEvent>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct ChannelView {
    pub name: String,
    pub head: Option<String>,
    pub head_subject: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct Snapshot {
    pub hosts: Vec<HostView>,
    pub channels: Vec<ChannelView>,
    pub promote_candidate: Option<String>,
    pub viewer: String,
    /// True only when the server runs in demo mode (simulated fleet).
    #[serde(default)]
    pub demo: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub struct AuditEvent {
    #[ts(type = "number")]
    pub id: i64,
    #[ts(type = "number")]
    pub time: i64,
    pub host: Option<String>,
    pub kind: String,
    pub actor: String,
    pub details: serde_json::Value,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, TS)]
#[serde(rename_all = "snake_case", tag = "type", content = "data")]
#[ts(export)]
pub enum WsMessage {
    Snapshot(Snapshot),
    HostUpdated(Box<HostView>),
    ChannelsUpdated(Vec<ChannelView>),
    ApplyLog(LogChunk),
}

/// True for exactly 40 lowercase hex characters.
pub fn is_commit_hash(s: &str) -> bool {
    s.len() == 40 && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commit_hash_validation() {
        assert!(is_commit_hash(&"a".repeat(40)));
        assert!(!is_commit_hash(&"a".repeat(39)));
        assert!(!is_commit_hash(&"A".repeat(40)));
        assert!(!is_commit_hash(&format!("{}-dirty", "a".repeat(40))));
    }

    #[test]
    fn ws_message_is_tagged() {
        let hv = HostView {
            name: "h".into(),
            os: "nixos".into(),
            channel: "stable".into(),
            online: OnlineState::On,
            last_seen: None,
            running: None,
            running_dirty: false,
            behind: None,
            checkout: None,
            last_apply: None,
            desired_apply_id: None,
            last_activation: None,
        };
        let s = serde_json::to_string(&WsMessage::HostUpdated(Box::new(hv))).unwrap();
        assert!(s.contains("\"type\":\"host_updated\""), "{s}");
        assert!(s.contains("\"data\":{"), "{s}");
    }
}
