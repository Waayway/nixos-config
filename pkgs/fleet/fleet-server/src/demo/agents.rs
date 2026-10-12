//! Simulated fleet agents: one in-process HTTP server per demo host, implementing the real
//! agent API (`GET /status`, `POST /apply`, `GET /apply/log`, `GET /activations`) with the
//! agent's status codes. An apply streams a realistic log over ~10 s (divided by the demo
//! speed) and ends as the host's script says.

use std::collections::VecDeque;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Context;
use axum::extract::{DefaultBodyLimit, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use fleet_proto::{
    ActivationEvent, ActivationsResponse, AgentStatus, ApplyRecord, ApplyRequest, ApplyState,
    CheckoutStatus, LogChunk, SkipReason, is_commit_hash,
};
use serde::Deserialize;
use tokio::task::JoinHandle;

use super::now;

const BODY_LIMIT: usize = 4096;
/// Applies kept, like the real agent.
const KEEP_APPLIES: usize = 50;
const AGENT_VERSION: &str = "0.1.0-demo";
/// Nix's base32 alphabet, for store path hashes.
const NIX_BASE32: &[u8] = b"0123456789abcdfghijklmnpqrsvwxyz";

/// How a simulated host's applies end.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Script {
    /// Every apply succeeds.
    Succeed,
    /// The checkout has tracked changes: every apply is skipped (`dirty`).
    Dirty,
    /// The first apply fails in `nix build`; later ones succeed.
    FailFirst,
}

/// A simulated host as its agent sees it.
pub struct HostSetup {
    pub name: String,
    pub os: String,
    pub channel: String,
    pub user: String,
    pub running: String,
    pub script: Script,
    /// Generation of the running system.
    pub generation: u64,
    /// When the initial manual activation happened (unix seconds).
    pub activated_at: i64,
}

struct Apply {
    rec: ApplyRecord,
    log: String,
}

struct Inner {
    running: String,
    checkout: CheckoutStatus,
    applies: VecDeque<Apply>,
    activations: Vec<ActivationEvent>,
    generation: u64,
    failed_once: bool,
}

pub struct SimAgent {
    name: String,
    os: String,
    script: Script,
    speed: f64,
    inner: Mutex<Inner>,
}

/// The real agent's apply id rule: `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`.
fn is_valid_apply_id(id: &str) -> bool {
    id.bytes().next().is_some_and(|b| b.is_ascii_alphanumeric())
        && id.len() <= 64
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// A fake but well-formed store path hash (32 chars of Nix base32), stable for `seed`.
fn store_hash(seed: &str) -> String {
    let mut out = String::with_capacity(32);
    let mut n = 0u64;
    while out.len() < 32 {
        let mut h = DefaultHasher::new();
        (seed, n).hash(&mut h);
        let mut v = h.finish();
        for _ in 0..12 {
            if out.len() == 32 {
                break;
            }
            out.push(NIX_BASE32[(v % 32) as usize] as char);
            v /= 32;
        }
        n += 1;
    }
    out
}

impl SimAgent {
    pub fn new(setup: HostSetup, speed: f64) -> SimAgent {
        let first = ActivationEvent {
            line: 0,
            time: setup.activated_at,
            store_path: system_path(&setup.name, &setup.os, &setup.running),
            revision: setup.running.clone(),
            generation: Some(setup.generation),
            trigger: "manual".into(),
            sudo_user: Some(setup.user.clone()),
        };
        let checkout = CheckoutStatus {
            branch: Some(setup.channel.clone()),
            head: Some(setup.running.clone()),
            dirty: setup.script == Script::Dirty,
            untracked: if setup.script == Script::Dirty { 2 } else { 0 },
            ahead: Some(0),
            last_fetch_at: Some(now() - 4 * 60),
        };
        SimAgent {
            name: setup.name,
            os: setup.os,
            script: setup.script,
            speed,
            inner: Mutex::new(Inner {
                running: setup.running,
                checkout,
                applies: VecDeque::new(),
                activations: vec![first],
                generation: setup.generation,
                failed_once: false,
            }),
        }
    }

    fn status(&self) -> AgentStatus {
        let inner = self.inner.lock().unwrap();
        AgentStatus {
            host: self.name.clone(),
            os: self.os.clone(),
            agent_version: AGENT_VERSION.into(),
            running: inner.running.clone(),
            checkout: inner.checkout.clone(),
            apply: inner.applies.back().map(|a| a.rec.clone()),
        }
    }

    fn append_log(&self, apply_id: &str, text: &str) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(a) = inner
            .applies
            .iter_mut()
            .find(|a| a.rec.apply_id == apply_id)
        {
            a.log.push_str(text);
            if !text.ends_with('\n') {
                a.log.push('\n');
            }
        }
    }

    fn scaled(&self, secs: f64) -> Duration {
        Duration::from_secs_f64(secs / self.speed)
    }

    /// Runs one apply: the log appears step by step, then the record gets its outcome.
    async fn run_apply(self: Arc<Self>, id: String, commit: String) {
        let short = &commit[..7];
        let hash = |what: &str| store_hash(&format!("{id}{what}"));
        let (head, channel) = {
            let inner = self.inner.lock().unwrap();
            (
                inner.checkout.head.clone().unwrap_or_default(),
                inner.checkout.branch.clone().unwrap_or_default(),
            )
        };
        let old = &head[..head.len().min(7)];

        let step = |secs: f64, text: String| {
            let agent = self.clone();
            let id = id.clone();
            async move {
                tokio::time::sleep(agent.scaled(secs)).await;
                agent.append_log(&id, &text);
            }
        };

        step(0.2, "==> git fetch".into()).await;
        step(
            1.0,
            format!(
                "From https://github.com/Waayway/nixos-config\n   {old}..{short}  {channel:<10} -> origin/{channel}"
            ),
        )
        .await;
        self.inner.lock().unwrap().checkout.last_fetch_at = Some(now());
        step(0.3, "==> checks".into()).await;
        if self.script == Script::Dirty {
            step(0.3, "==> skipped: Dirty".into()).await;
            self.finish(&id, |rec| {
                rec.state = ApplyState::Skipped;
                rec.skip_reason = Some(SkipReason::Dirty);
                rec.message = Some("skipped: Dirty".into());
            });
            return;
        }
        step(
            0.3,
            format!("==> git merge --ff-only\nUpdating {old}..{short}\nFast-forward"),
        )
        .await;
        self.inner.lock().unwrap().checkout.head = Some(commit.clone());

        let (attr, system_drv) = if self.os == "darwin" {
            (
                format!("darwinConfigurations.{}.system", self.name),
                format!("darwin-system-25.11.{short}"),
            )
        } else {
            (
                format!(
                    "nixosConfigurations.{}.config.system.build.toplevel",
                    self.name
                ),
                format!("nixos-system-{}-25.11.20261010.{short}", self.name),
            )
        };
        step(
            0.4,
            format!(
                "==> nix build\nevaluating {attr}\nthese 4 derivations will be built:\n  /nix/store/{}-home-manager-files.drv\n  /nix/store/{}-home-manager-generation.drv\n  /nix/store/{}-etc.drv\n  /nix/store/{}-{system_drv}.drv",
                hash("hmf"),
                hash("hmg"),
                hash("etc"),
                hash("sys"),
            ),
        )
        .await;
        step(
            1.4,
            format!(
                "building '/nix/store/{}-home-manager-files.drv'...",
                hash("hmf")
            ),
        )
        .await;
        let fail = self.script == Script::FailFirst && !self.inner.lock().unwrap().failed_once;
        step(
            1.6,
            format!(
                "building '/nix/store/{}-home-manager-generation.drv'...",
                hash("hmg")
            ),
        )
        .await;
        if fail {
            step(
                1.2,
                format!(
                    "error: builder for '/nix/store/{}-home-manager-generation.drv' failed with exit code 1\n==> nix build failed (exit status: 1)",
                    hash("hmg")
                ),
            )
            .await;
            self.inner.lock().unwrap().failed_once = true;
            self.finish(&id, |rec| {
                rec.state = ApplyState::Failed;
                rec.exit_code = Some(1);
                rec.message = Some("nix build failed (exit status: 1)".into());
            });
            return;
        }
        step(
            1.2,
            format!("building '/nix/store/{}-etc.drv'...", hash("etc")),
        )
        .await;
        step(
            1.4,
            format!("building '/nix/store/{}-{system_drv}.drv'...", hash("sys")),
        )
        .await;
        let out = system_path(&self.name, &self.os, &commit);
        step(0.6, out.clone()).await;
        step(0.3, "==> nix-env --set".into()).await;
        let activation = if self.os == "darwin" {
            "==> activate\nsetting up groups...\nsetting up users...\nsetting up /Applications/Nix Apps...\nsetting up pam...\nactivating home-manager configuration for demo"
        } else {
            "==> switch-to-configuration\nactivating the configuration...\nsetting up /etc...\nreloading user units for demo...\nrestarting sysinit-reactivation.target\nthe following new units were started: nix-gc.timer"
        };
        step(0.8, activation.into()).await;

        let time = now();
        let mut inner = self.inner.lock().unwrap();
        inner.generation += 1;
        let ev = ActivationEvent {
            line: inner.activations.len() as u64,
            time,
            store_path: out,
            revision: commit.clone(),
            generation: Some(inner.generation),
            trigger: format!("apply:{id}"),
            sudo_user: None,
        };
        inner.activations.push(ev);
        inner.running = commit;
        drop(inner);
        self.finish(&id, |rec| {
            rec.state = ApplyState::Ok;
            rec.exit_code = Some(0);
        });
    }

    fn finish(&self, id: &str, outcome: impl FnOnce(&mut ApplyRecord)) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(a) = inner.applies.iter_mut().find(|a| a.rec.apply_id == id) {
            outcome(&mut a.rec);
            a.rec.finished_at = Some(now());
        }
    }
}

/// `/nix/store/<hash>-<name>` of the system built from `commit`.
fn system_path(host: &str, os: &str, commit: &str) -> String {
    let short = &commit[..commit.len().min(7)];
    let name = if os == "darwin" {
        format!("darwin-system-25.11.{short}")
    } else {
        format!("nixos-system-{host}-25.11.20261010.{short}")
    };
    format!(
        "/nix/store/{}-{name}",
        store_hash(&format!("{host}{commit}"))
    )
}

async fn get_status(State(agent): State<Arc<SimAgent>>) -> Json<AgentStatus> {
    Json(agent.status())
}

async fn post_apply(State(agent): State<Arc<SimAgent>>, Json(req): Json<ApplyRequest>) -> Response {
    if !is_commit_hash(&req.commit) || !is_valid_apply_id(&req.apply_id) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    {
        let mut inner = agent.inner.lock().unwrap();
        if let Some(a) = inner
            .applies
            .iter()
            .find(|a| a.rec.apply_id == req.apply_id)
        {
            return (StatusCode::OK, Json(a.rec.clone())).into_response();
        }
        if inner
            .applies
            .back()
            .is_some_and(|a| a.rec.state == ApplyState::Running)
        {
            return StatusCode::CONFLICT.into_response();
        }
        inner.applies.push_back(Apply {
            rec: ApplyRecord {
                apply_id: req.apply_id.clone(),
                commit: req.commit.clone(),
                state: ApplyState::Running,
                skip_reason: None,
                message: None,
                exit_code: None,
                started_at: Some(now()),
                finished_at: None,
            },
            log: String::new(),
        });
        while inner.applies.len() > KEEP_APPLIES {
            inner.applies.pop_front();
        }
    }
    tokio::spawn(agent.clone().run_apply(req.apply_id, req.commit));
    StatusCode::ACCEPTED.into_response()
}

#[derive(Deserialize)]
struct LogQuery {
    apply_id: String,
    #[serde(default)]
    offset: u64,
}

async fn get_log(State(agent): State<Arc<SimAgent>>, Query(q): Query<LogQuery>) -> Response {
    let inner = agent.inner.lock().unwrap();
    let Some(a) = inner.applies.iter().find(|a| a.rec.apply_id == q.apply_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let data = usize::try_from(q.offset)
        .ok()
        .and_then(|o| a.log.get(o..))
        .unwrap_or_default()
        .to_string();
    let at_end = q.offset + data.len() as u64 >= a.log.len() as u64;
    Json(LogChunk {
        apply_id: q.apply_id,
        offset: q.offset,
        next: q.offset + data.len() as u64,
        data,
        eof: at_end && a.rec.state != ApplyState::Running,
    })
    .into_response()
}

#[derive(Deserialize)]
struct SinceQuery {
    #[serde(default)]
    since: u64,
}

async fn get_activations(
    State(agent): State<Arc<SimAgent>>,
    Query(q): Query<SinceQuery>,
) -> Json<ActivationsResponse> {
    let inner = agent.inner.lock().unwrap();
    Json(ActivationsResponse {
        events: inner
            .activations
            .iter()
            .filter(|e| e.line >= q.since)
            .cloned()
            .collect(),
        next: inner.activations.len() as u64,
    })
}

pub fn router(agent: Arc<SimAgent>) -> Router {
    Router::new()
        .route("/status", get(get_status))
        .route("/apply", post(post_apply))
        .route("/apply/log", get(get_log))
        .route("/activations", get(get_activations))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
        .with_state(agent)
}

/// Serves a simulated agent on `127.0.0.1:0`; returns its address and the server task.
pub async fn serve(agent: Arc<SimAgent>) -> anyhow::Result<(SocketAddr, JoinHandle<()>)> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .context("binding a simulated agent")?;
    let addr = listener.local_addr()?;
    let name = agent.name.clone();
    let task = tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, router(agent)).await {
            eprintln!("fleet-server: demo agent {name}: {e}");
        }
    });
    Ok((addr, task))
}
