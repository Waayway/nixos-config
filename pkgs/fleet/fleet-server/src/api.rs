//! The dashboard HTTP surface: JSON API under `/api`, the WebSocket at `/api/ws`, and the
//! embedded frontend for everything else. Every route, the WebSocket upgrade and the static
//! files included, sits behind `require_access`.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path, Query, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router, middleware};
use fleet_proto::{ApplyRecord, ApplyRequest, ApplyState, AuditEvent, Snapshot, WsMessage};
use futures::future::join_all;
use sea_orm::TransactionTrait;
use serde::Deserialize;
use serde_json::{Value, json};

use crate::access::{AccessState, Actor, require_access};
use crate::config::FleetHost;
use crate::db;
use crate::mirror::PromoteError;
use crate::poller::agent_base;
use crate::state::{AppState, channels, host_view, snapshot};
use crate::{embed, ws};

const AUDIT_DEFAULT_LIMIT: u64 = 100;
const AUDIT_MAX_LIMIT: u64 = 1000;

/// The complete dashboard app. Serve it with
/// `into_make_service_with_connect_info::<SocketAddr>()` (access control needs the peer).
pub fn app(state: AppState) -> Router {
    let access = AccessState {
        provider: state.online.clone(),
        cfg: Arc::new(state.cfg.access.clone()),
    };
    let api = Router::new()
        .route("/snapshot", get(get_snapshot))
        .route("/hosts/{name}/apply", post(apply_host))
        .route("/channels/{channel}/apply", post(apply_channel))
        .route("/promote", post(promote))
        .route("/hosts/{name}/applies/{id}/log", get(apply_log))
        .route("/audit", get(audit))
        .route("/ws", get(ws::handler))
        .fallback(|| async { ApiError(StatusCode::NOT_FOUND, "not found".into()) });
    Router::new()
        .nest("/api", api)
        .fallback(embed::static_handler)
        .layer(middleware::from_fn_with_state(access, require_access))
        .with_state(state)
}

/// An error answer: `{"error": "..."}` with the status.
#[derive(Debug)]
struct ApiError(StatusCode, String);

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({ "error": self.1 }))).into_response()
    }
}

fn internal(e: anyhow::Error) -> ApiError {
    eprintln!("fleet-server: api: {e:#}");
    ApiError(StatusCode::INTERNAL_SERVER_ERROR, format!("{e:#}"))
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

fn find_host<'a>(state: &'a AppState, name: &str) -> Result<&'a FleetHost, ApiError> {
    state
        .hosts
        .iter()
        .find(|h| h.name.eq_ignore_ascii_case(name))
        .ok_or_else(|| ApiError(StatusCode::NOT_FOUND, format!("unknown host {name}")))
}

async fn fetch_mirror(state: &AppState) -> Result<(), ApiError> {
    state.mirror.fetch().await.map_err(|e| {
        eprintln!("fleet-server: api: mirror fetch: {e:#}");
        ApiError(
            StatusCode::BAD_GATEWAY,
            format!("mirror fetch failed: {e:#}"),
        )
    })
}

async fn channel_head(state: &AppState, channel: &str) -> Result<String, ApiError> {
    state.mirror.head(channel).await.ok_or_else(|| {
        ApiError(
            StatusCode::CONFLICT,
            format!("channel {channel} has no head in the mirror"),
        )
    })
}

async fn get_snapshot(
    State(state): State<AppState>,
    Extension(Actor(viewer)): Extension<Actor>,
) -> Json<Snapshot> {
    Json(snapshot(&state, viewer).await)
}

/// Creates one new apply of `commit` per host and makes it the host's desired apply, with an
/// `apply_requested` audit row each, all in one transaction. Returns the new ids.
async fn create_applies(
    state: &AppState,
    actor: &str,
    hosts: &[&FleetHost],
    commit: &str,
) -> anyhow::Result<Vec<String>> {
    let at = now();
    let txn = state.db.begin().await?;
    let mut ids = Vec::with_capacity(hosts.len());
    for host in hosts {
        let rec = ApplyRecord {
            apply_id: uuid::Uuid::new_v4().to_string(),
            commit: commit.to_string(),
            state: ApplyState::Idle,
            skip_reason: None,
            message: None,
            exit_code: None,
            started_at: None,
            finished_at: None,
        };
        db::insert_apply(&txn, &host.name, actor, at, &rec).await?;
        db::set_desired(&txn, &host.name, &rec.apply_id).await?;
        let details = json!({
            "apply_id": rec.apply_id,
            "commit": commit,
            "channel": host.channel,
        });
        db::insert_audit(
            &txn,
            at,
            Some(&host.name),
            "apply_requested",
            actor,
            details,
        )
        .await?;
        ids.push(rec.apply_id);
    }
    txn.commit().await?;
    for host in hosts {
        let view = host_view(state, host).await;
        state.broadcast(WsMessage::HostUpdated(Box::new(view)));
    }
    Ok(ids)
}

/// Sends the apply to the host's agent. Returns the agent's answer: `"202"` (started), `"200"`
/// (already ran), `"409"` (busy), `"unreachable"` (offline or no answer) or `"error"`. The
/// poller re-sends a desired apply the agent never received.
async fn send_apply(state: &AppState, host: &FleetHost, apply_id: &str, commit: &str) -> String {
    let peers = state.online.peers().await;
    let Some(base) = agent_base(&state.cfg, host, &peers) else {
        return "unreachable".into();
    };
    let req = ApplyRequest {
        apply_id: apply_id.to_string(),
        commit: commit.to_string(),
    };
    match state.client.apply(&base, &req).await {
        Ok(code) if matches!(code.as_u16(), 200 | 202 | 409) => code.as_u16().to_string(),
        Ok(code) => {
            eprintln!(
                "fleet-server: {}: apply {apply_id}: agent answered {code}",
                host.name
            );
            "error".into()
        }
        Err(e) => {
            eprintln!("fleet-server: {}: apply {apply_id}: {e:#}", host.name);
            "unreachable".into()
        }
    }
}

async fn apply_host(
    State(state): State<AppState>,
    Extension(Actor(actor)): Extension<Actor>,
    Path(name): Path<String>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let host = find_host(&state, &name)?;
    fetch_mirror(&state).await?;
    let commit = channel_head(&state, &host.channel).await?;
    let ids = create_applies(&state, &actor, &[host], &commit)
        .await
        .map_err(internal)?;
    let apply_id = &ids[0];
    let agent_status = send_apply(&state, host, apply_id, &commit).await;
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({ "apply_id": apply_id, "agent_status": agent_status })),
    ))
}

async fn apply_channel(
    State(state): State<AppState>,
    Extension(Actor(actor)): Extension<Actor>,
    Path(channel): Path<String>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let hosts: Vec<&FleetHost> = state
        .hosts
        .iter()
        .filter(|h| h.channel == channel)
        .collect();
    if hosts.is_empty() {
        return Err(ApiError(
            StatusCode::NOT_FOUND,
            format!("no fleet host on channel {channel}"),
        ));
    }
    fetch_mirror(&state).await?;
    let commit = channel_head(&state, &channel).await?;
    let ids = create_applies(&state, &actor, &hosts, &commit)
        .await
        .map_err(internal)?;
    let statuses = join_all(
        hosts
            .iter()
            .zip(&ids)
            .map(|(h, id)| send_apply(&state, h, id, &commit)),
    )
    .await;
    let mut apply_ids = BTreeMap::new();
    let mut agent_status = BTreeMap::new();
    for ((host, id), status) in hosts.iter().zip(ids).zip(statuses) {
        apply_ids.insert(host.name.clone(), id);
        agent_status.insert(host.name.clone(), status);
    }
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({ "apply_ids": apply_ids, "agent_status": agent_status })),
    ))
}

#[derive(Deserialize)]
struct PromoteBody {
    commit: String,
}

async fn promote(
    State(state): State<AppState>,
    Extension(Actor(actor)): Extension<Actor>,
    Json(body): Json<PromoteBody>,
) -> Result<Json<Value>, ApiError> {
    if !fleet_proto::is_commit_hash(&body.commit) {
        return Err(ApiError(
            StatusCode::BAD_REQUEST,
            "commit must be 40 lowercase hex characters".into(),
        ));
    }
    fetch_mirror(&state).await?;
    let previous = state.mirror.head("stable").await;
    state
        .mirror
        .promote(&body.commit)
        .await
        .map_err(|e| match e {
            PromoteError::Rejected(msg) => ApiError(StatusCode::CONFLICT, msg),
            PromoteError::Git(e) => {
                eprintln!("fleet-server: api: promote: {e:#}");
                ApiError(StatusCode::BAD_GATEWAY, format!("promote failed: {e:#}"))
            }
        })?;
    // The push happened; a failure to record it must not turn the answer into an error.
    let details = json!({ "commit": body.commit, "previous": previous });
    if let Err(e) = db::insert_audit(&state.db, now(), None, "promote", &actor, details).await {
        eprintln!("fleet-server: api: auditing promote: {e:#}");
    }
    if let Err(e) = state.mirror.fetch().await {
        eprintln!("fleet-server: api: mirror fetch after promote: {e:#}");
    }
    state.broadcast(WsMessage::ChannelsUpdated(channels(&state).await));
    Ok(Json(json!({ "commit": body.commit })))
}

/// The server's stored copy of an apply's log, or else the agent's live log from the start.
async fn apply_log(
    State(state): State<AppState>,
    Path((name, id)): Path<(String, String)>,
) -> Result<Response, ApiError> {
    let host = find_host(&state, &name)?;
    let row = db::get_apply(&state.db, &id)
        .await
        .map_err(internal)?
        .filter(|r| r.host == host.name)
        .ok_or_else(|| ApiError(StatusCode::NOT_FOUND, format!("unknown apply {id}")))?;
    let log = match row.log {
        Some(log) => log,
        None => {
            let peers = state.online.peers().await;
            let base = agent_base(&state.cfg, host, &peers).ok_or_else(|| {
                ApiError(
                    StatusCode::SERVICE_UNAVAILABLE,
                    format!("{} is offline", host.name),
                )
            })?;
            state
                .client
                .log(&base, &id, 0)
                .await
                .map_err(|e| ApiError(StatusCode::BAD_GATEWAY, format!("{e:#}")))?
                .data
        }
    };
    Ok(([(header::CONTENT_TYPE, "text/plain; charset=utf-8")], log).into_response())
}

#[derive(Deserialize)]
struct AuditQuery {
    limit: Option<u64>,
}

async fn audit(
    State(state): State<AppState>,
    Query(q): Query<AuditQuery>,
) -> Result<Json<Vec<AuditEvent>>, ApiError> {
    let limit = q
        .limit
        .unwrap_or(AUDIT_DEFAULT_LIMIT)
        .clamp(1, AUDIT_MAX_LIMIT);
    db::recent_audit(&state.db, limit)
        .await
        .map(Json)
        .map_err(internal)
}
