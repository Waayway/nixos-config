//! The agent's HTTP API and daemon loop.

use std::collections::HashSet;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::{ConnectInfo, DefaultBodyLimit, Query, Request, State};
use axum::http::StatusCode;
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use fleet_proto::{ApplyRequest, ApplyState, is_commit_hash};
use serde::Deserialize;
use tokio::sync::{Mutex, OwnedMutexGuard};

use crate::apply::{
    is_valid_apply_id, latest_record, read_log, read_record, record_fetch, try_lock_apply,
};
use crate::config::AgentConfig;
use crate::git::Git;
use crate::net::{SourceGuard, tailscale_addrs};
use crate::{activations, launcher, status};

const BODY_LIMIT: usize = 4096;
const FETCH_INTERVAL: Duration = Duration::from_secs(600);
const PENDING_TTL: Duration = Duration::from_secs(30);
const ADDR_RECHECK: Duration = Duration::from_secs(60);

type Pending = (String, Instant);

#[derive(Clone)]
pub struct AppState {
    cfg: Arc<AgentConfig>,
    config_path: Arc<PathBuf>,
    git: Arc<Git>,
    guard: Arc<SourceGuard>,
    /// Serialises the "is anything running?" check with the launch (and the
    /// background fetch). Holds the apply launched but not yet visible as a
    /// record, for up to `PENDING_TTL`.
    apply_lock: Arc<Mutex<Option<Pending>>>,
}

impl AppState {
    /// `config_path` is handed to the apply wrapper, which re-reads it.
    pub fn new(
        cfg: AgentConfig,
        config_path: PathBuf,
        guard: SourceGuard,
    ) -> anyhow::Result<AppState> {
        Ok(AppState {
            git: Arc::new(Git::new(&cfg)?),
            cfg: Arc::new(cfg),
            config_path: Arc::new(config_path),
            guard: Arc::new(guard),
            apply_lock: Arc::new(Mutex::new(None)),
        })
    }
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/status", get(get_status))
        .route("/apply", post(post_apply))
        .route("/apply/log", get(get_log))
        .route("/activations", get(get_activations))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
        .layer(middleware::from_fn_with_state(state.clone(), check_source))
        .with_state(state)
}

async fn check_source(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    req: Request,
    next: Next,
) -> Response {
    if st.guard.allows(peer.ip()).await {
        next.run(req).await
    } else {
        StatusCode::FORBIDDEN.into_response()
    }
}

fn internal<E: std::fmt::Display>(e: E) -> Response {
    eprintln!("fleet-agent: {e}");
    StatusCode::INTERNAL_SERVER_ERROR.into_response()
}

async fn get_status(State(st): State<AppState>) -> Response {
    match tokio::task::spawn_blocking(move || status::collect(&st.cfg, &st.git)).await {
        Ok(s) => Json(s).into_response(),
        Err(e) => internal(e),
    }
}

async fn post_apply(State(st): State<AppState>, Json(req): Json<ApplyRequest>) -> Response {
    if !is_commit_hash(&req.commit) || !is_valid_apply_id(&req.apply_id) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let guard = st.apply_lock.clone().lock_owned().await;
    let res = tokio::task::spawn_blocking(move || launch_apply(st, guard, req)).await;
    res.unwrap_or_else(internal)
}

/// The pending apply, if its record has not appeared yet and it is recent.
fn live_pending(st: &AppState, pending: &mut Option<Pending>) -> Option<String> {
    if let Some((id, at)) = pending.as_ref()
        && (at.elapsed() >= PENDING_TTL || read_record(&st.cfg, id).is_some())
    {
        *pending = None;
    }
    pending.as_ref().map(|(id, _)| id.clone())
}

fn launch_apply(
    st: AppState,
    mut guard: OwnedMutexGuard<Option<Pending>>,
    req: ApplyRequest,
) -> Response {
    let pending = live_pending(&st, &mut guard);
    if let Some(rec) = read_record(&st.cfg, &req.apply_id) {
        return (StatusCode::OK, Json(rec)).into_response();
    }
    if let Some(id) = pending {
        return if id == req.apply_id {
            StatusCode::ACCEPTED.into_response()
        } else {
            StatusCode::CONFLICT.into_response()
        };
    }
    if latest_record(&st.cfg).is_some_and(|r| r.state == ApplyState::Running) {
        return StatusCode::CONFLICT.into_response();
    }
    match launcher::launch(&st.cfg, &st.config_path, &req.apply_id, &req.commit) {
        Ok(()) => {
            *guard = Some((req.apply_id, Instant::now()));
            StatusCode::ACCEPTED.into_response()
        }
        Err(e) => internal(format!("launching apply: {e:#}")),
    }
}

#[derive(Deserialize)]
struct LogQuery {
    apply_id: String,
    #[serde(default)]
    offset: u64,
}

async fn get_log(State(st): State<AppState>, Query(q): Query<LogQuery>) -> Response {
    let res = tokio::task::spawn_blocking(move || read_log(&st.cfg, &q.apply_id, q.offset)).await;
    match res {
        Ok(Some(chunk)) => Json(chunk).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(e) => internal(e),
    }
}

#[derive(Deserialize)]
struct SinceQuery {
    #[serde(default)]
    since: u64,
}

async fn get_activations(State(st): State<AppState>, Query(q): Query<SinceQuery>) -> Response {
    let path = st.cfg.state_dir.join("activations.jsonl");
    match tokio::task::spawn_blocking(move || activations::read_since(&path, q.since)).await {
        Ok(r) => Json(r).into_response(),
        Err(e) => internal(e),
    }
}

// ---- daemon ----

async fn serve_on(listener: tokio::net::TcpListener, app: Router) {
    let app = app.into_make_service_with_connect_info::<SocketAddr>();
    if let Err(e) = axum::serve(listener, app).await {
        eprintln!("fleet-agent: server stopped: {e}");
    }
}

/// Every 600 s, unless an apply is running or starting. Holds the apply lock
/// throughout so it never overlaps with an apply's own fetch.
async fn background_fetch(st: AppState) {
    loop {
        tokio::time::sleep(FETCH_INTERVAL).await;
        let mut guard = st.apply_lock.clone().lock_owned().await;
        let st = st.clone();
        let _ = tokio::task::spawn_blocking(move || {
            if live_pending(&st, &mut guard).is_some()
                || latest_record(&st.cfg).is_some_and(|r| r.state == ApplyState::Running)
            {
                return;
            }
            // The wrapper may be running without a record yet (or a daemon restart).
            let Some(_flock) = try_lock_apply(&st.cfg) else {
                return;
            };
            match st.git.fetch(&st.cfg.repo_url) {
                Ok(()) => record_fetch(&st.cfg),
                Err(e) => eprintln!("fleet-agent: background fetch failed: {e:#}"),
            }
        })
        .await;
    }
}

/// Runs the daemon: binds `listen`, or every Tailscale address (retrying with
/// backoff and re-checking the addresses every 60 s), and serves forever.
pub async fn serve(cfg: AgentConfig, config_path: PathBuf) -> anyhow::Result<()> {
    let state = AppState::new(
        cfg.clone(),
        config_path,
        SourceGuard::new(cfg.manager_host.clone()),
    )?;
    tokio::spawn(background_fetch(state.clone()));
    let app = router(state);

    if let Some(addr) = cfg.listen {
        let listener = tokio::net::TcpListener::bind(addr).await?;
        eprintln!("fleet-agent: listening on {addr}");
        serve_on(listener, app).await;
        anyhow::bail!("server exited");
    }

    let mut bound: HashSet<IpAddr> = HashSet::new();
    let mut backoff = Duration::from_secs(1);
    loop {
        let mut pending = tailscale_addrs().is_empty();
        for ip in tailscale_addrs() {
            if bound.contains(&ip) {
                continue;
            }
            match tokio::net::TcpListener::bind(SocketAddr::new(ip, cfg.port)).await {
                Ok(l) => {
                    eprintln!(
                        "fleet-agent: listening on {}",
                        SocketAddr::new(ip, cfg.port)
                    );
                    bound.insert(ip);
                    tokio::spawn(serve_on(l, app.clone()));
                }
                Err(e) => {
                    eprintln!("fleet-agent: cannot bind {ip}:{}: {e}", cfg.port);
                    pending = true;
                }
            }
        }
        if pending {
            tokio::time::sleep(backoff).await;
            backoff = (backoff * 2).min(ADDR_RECHECK);
        } else {
            backoff = Duration::from_secs(1);
            tokio::time::sleep(ADDR_RECHECK).await;
        }
    }
}
