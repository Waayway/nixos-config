//! Polls every fleet host's agent: status, apply transitions, activations, re-sends of a
//! missed desired apply, live apply logs. Every change is broadcast to dashboard clients.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use fleet_proto::{AgentStatus, ApplyRecord, ApplyRequest, ApplyState, WsMessage};
use futures::future::join_all;
use sea_orm::TransactionTrait;
use tokio::time::MissedTickBehavior;

use crate::config::{FleetHost, OnlineSource, ServerConfig};
use crate::db;
use crate::resend::should_resend;
use crate::state::{AppState, channels, host_view_with};
use crate::tailscale::PeerInfo;

const LOG_INTERVAL: Duration = Duration::from_secs(2);
/// A follower gives up after this many failed log reads in a row.
const LOG_MAX_ERRORS: u32 = 5;

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

fn log_err<T>(what: &str, host: &str, r: anyhow::Result<T>) -> Option<T> {
    r.map_err(|e| eprintln!("fleet-server: {host}: {what}: {e:#}"))
        .ok()
}

/// `host:port` of a host's agent, or `None` when Tailscale doesn't report it online with an
/// address. With `OnlineSource::Static`, an address that already has a port (tests/dev only)
/// is used as-is; otherwise `agent_port` is appended.
pub fn agent_base(
    cfg: &ServerConfig,
    host: &FleetHost,
    peers: &HashMap<String, PeerInfo>,
) -> Option<String> {
    let peer = peers.get(&host.name.to_lowercase())?;
    let ip = peer.addr.filter(|_| peer.online)?;
    if let OnlineSource::Static { addresses } = &cfg.online
        && let Some(with_port) = addresses
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case(&host.name))
            .and_then(|(_, a)| a.parse::<SocketAddr>().ok())
    {
        return Some(with_port.to_string());
    }
    Some(SocketAddr::new(ip, cfg.agent_port).to_string())
}

/// Polls all hosts concurrently.
pub async fn poll_once(state: &AppState) {
    let peers = state.online.peers().await;
    join_all(state.hosts.iter().map(|h| poll_host(state, h, &peers))).await;
}

async fn poll_host(state: &AppState, host: &FleetHost, peers: &HashMap<String, PeerInfo>) {
    let status = match agent_base(&state.cfg, host, peers) {
        Some(base) => match state.client.status(&base).await {
            Ok(s) => Some((base, s)),
            Err(e) => {
                eprintln!("fleet-server: {}: agent unreachable: {e:#}", host.name);
                None
            }
        },
        None => None,
    };
    state
        .reachable
        .lock()
        .unwrap()
        .insert(host.name.clone(), status.is_some());
    if let Some((base, status)) = status {
        handle_status(state, host, &base, &status).await;
    }
    let view = host_view_with(state, host, peers).await;
    state.broadcast(WsMessage::HostUpdated(Box::new(view)));
}

async fn handle_status(state: &AppState, host: &FleetHost, base: &str, status: &AgentStatus) {
    let name = host.name.as_str();
    log_err(
        "saving status",
        name,
        db::save_status(&state.db, name, status, now()).await,
    );
    if let Some(rec) = &status.apply {
        log_err(
            "recording apply",
            name,
            record_apply(state, host, base, rec).await,
        );
    }
    log_err(
        "ingesting activations",
        name,
        ingest_activations(state, name, base).await,
    );
    let desired = log_err(
        "loading desired apply",
        name,
        db::desired(&state.db, name).await,
    )
    .flatten();
    let (id, commit) = match &desired {
        Some(d) => (Some(d.apply_id.as_str()), Some(d.commit.as_str())),
        None => (None, None),
    };
    if should_resend(id, commit, status)
        && let Some(d) = &desired
    {
        let req = ApplyRequest {
            apply_id: d.apply_id.clone(),
            commit: d.commit.clone(),
        };
        if let Some(code) = log_err(
            "re-sending desired apply",
            name,
            state.client.apply(base, &req).await,
        ) {
            eprintln!(
                "fleet-server: {name}: re-sent apply {} ({}): {code}",
                req.apply_id, req.commit
            );
        }
    }
}

fn state_str(s: &ApplyState) -> &'static str {
    match s {
        ApplyState::Idle => "idle",
        ApplyState::Running => "running",
        ApplyState::Ok => "ok",
        ApplyState::Skipped => "skipped",
        ApplyState::Failed => "failed",
    }
}

fn is_terminal(s: &str) -> bool {
    matches!(s, "ok" | "skipped" | "failed")
}

/// Mirrors the agent's latest apply record into the server's copy. On the first terminal
/// state: audit `apply_finished` and store the full log. The log is fetched before any row
/// is touched, and the row update, audit row and log are written in one transaction, so a
/// failure leaves the row non-terminal and the next poll retries. Applies the server didn't
/// create are ignored. A running apply gets a log follower.
async fn record_apply(
    state: &AppState,
    host: &FleetHost,
    base: &str,
    rec: &ApplyRecord,
) -> anyhow::Result<()> {
    if rec.state == ApplyState::Running {
        let (st, h, id) = (state.clone(), host.clone(), rec.apply_id.clone());
        tokio::spawn(async move { follow_log(&st, &h, &id).await });
    }
    let Some(row) = db::get_apply(&state.db, &rec.apply_id).await? else {
        return Ok(());
    };
    if row.host != host.name || is_terminal(&row.state) {
        return Ok(());
    }
    let new_state = state_str(&rec.state);
    if row.state == new_state {
        return Ok(());
    }
    if !is_terminal(new_state) {
        return db::update_apply_from_record(&state.db, rec).await;
    }
    let log = read_full_log(state, base, &rec.apply_id).await?;
    let details = serde_json::to_value(rec)?;
    let txn = state.db.begin().await?;
    db::update_apply_from_record(&txn, rec).await?;
    db::insert_audit(
        &txn,
        rec.finished_at.unwrap_or_else(now),
        Some(&host.name),
        "apply_finished",
        "agent",
        details,
    )
    .await?;
    db::set_apply_log(&txn, &rec.apply_id, &log).await?;
    txn.commit().await?;
    Ok(())
}

/// Reads a finished apply's log from the start to eof.
async fn read_full_log(state: &AppState, base: &str, apply_id: &str) -> anyhow::Result<String> {
    let mut log = String::new();
    loop {
        let chunk = state.client.log(base, apply_id, log.len() as u64).await?;
        log.push_str(&chunk.data);
        if chunk.eof || chunk.data.is_empty() {
            return Ok(log);
        }
    }
}

/// Copies new activation lines into the audit log (kind `activation`). Rows and the
/// cursor are written in one transaction, so a failure never duplicates rows.
async fn ingest_activations(state: &AppState, host: &str, base: &str) -> anyhow::Result<()> {
    let since = db::activations_next(&state.db, host).await?;
    let resp = state.client.activations(base, since.max(0) as u64).await?;
    let next = resp.next as i64;
    if resp.events.is_empty() && next == since {
        return Ok(());
    }
    let txn = state.db.begin().await?;
    for ev in &resp.events {
        let actor = ev.sudo_user.clone().unwrap_or_else(|| ev.trigger.clone());
        db::insert_audit(
            &txn,
            ev.time,
            Some(host),
            "activation",
            &actor,
            serde_json::to_value(ev)?,
        )
        .await?;
    }
    db::set_activations_next(&txn, host, next).await?;
    txn.commit().await?;
    Ok(())
}

/// Removes the follower entry when the follower ends, however it ends.
struct FollowerGuard<'a> {
    state: &'a AppState,
    key: (String, String),
}

impl Drop for FollowerGuard<'_> {
    fn drop(&mut self) {
        self.state.followers.lock().unwrap().remove(&self.key);
    }
}

/// Streams a running apply's log to dashboard clients every 2 s; at eof stores the full log.
/// At most one follower runs per `(host, apply_id)`.
pub async fn follow_log(state: &AppState, host: &FleetHost, apply_id: &str) {
    let key = (host.name.clone(), apply_id.to_string());
    if !state.followers.lock().unwrap().insert(key.clone()) {
        return;
    }
    let _guard = FollowerGuard { state, key };
    let peers = state.online.peers().await;
    let Some(base) = agent_base(&state.cfg, host, &peers) else {
        return;
    };
    let mut log = String::new();
    let mut errors = 0;
    loop {
        match state.client.log(&base, apply_id, log.len() as u64).await {
            Ok(chunk) => {
                errors = 0;
                log.push_str(&chunk.data);
                let eof = chunk.eof;
                if !chunk.data.is_empty() || eof {
                    state.broadcast(WsMessage::ApplyLog(chunk));
                }
                if eof {
                    if db::get_apply(&state.db, apply_id)
                        .await
                        .ok()
                        .flatten()
                        .is_some()
                    {
                        log_err(
                            "storing apply log",
                            &host.name,
                            db::set_apply_log(&state.db, apply_id, &log).await,
                        );
                    }
                    return;
                }
            }
            Err(e) => {
                errors += 1;
                if errors >= LOG_MAX_ERRORS {
                    eprintln!(
                        "fleet-server: {}: giving up on log of {apply_id}: {e:#}",
                        host.name
                    );
                    return;
                }
            }
        }
        tokio::time::sleep(LOG_INTERVAL).await;
    }
}

/// Background loops: mirror fetch every `mirror_fetch_secs` (then `ChannelsUpdated`) and
/// agent polling every `poll_secs`. Both run once immediately.
pub fn spawn(state: AppState) {
    let st = state.clone();
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(st.cfg.mirror_fetch_secs.max(1)));
        tick.set_missed_tick_behavior(MissedTickBehavior::Delay);
        loop {
            tick.tick().await;
            if let Err(e) = st.mirror.fetch().await {
                eprintln!("fleet-server: mirror fetch: {e:#}");
            }
            st.broadcast(WsMessage::ChannelsUpdated(channels(&st).await));
        }
    });
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(state.cfg.poll_secs.max(1)));
        tick.set_missed_tick_behavior(MissedTickBehavior::Delay);
        loop {
            tick.tick().await;
            poll_once(&state).await;
        }
    });
}
