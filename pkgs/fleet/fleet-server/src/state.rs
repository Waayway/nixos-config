//! Shared server state and the dashboard views built from it.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::{Arc, Mutex};

use fleet_proto::{ActivationEvent, ChannelView, HostView, OnlineState, Snapshot, WsMessage};
use futures::future::join_all;
use sea_orm::DatabaseConnection;
use tokio::sync::broadcast;

use crate::agent_client::AgentClient;
use crate::config::{FleetHost, ServerConfig};
use crate::db;
use crate::mirror::Mirror;
use crate::tailscale::{OnlineProvider, PeerInfo};

const BROADCAST_CAPACITY: usize = 256;

#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub mirror: Arc<Mirror>,
    pub online: Arc<dyn OnlineProvider>,
    pub client: AgentClient,
    pub hosts: Vec<FleetHost>,
    pub tx: broadcast::Sender<WsMessage>,
    pub cfg: Arc<ServerConfig>,
    /// Hosts whose last `GET /status` succeeded (by host name).
    pub(crate) reachable: Arc<Mutex<HashMap<String, bool>>>,
    /// `(host, apply_id)` pairs with a live log follower.
    pub(crate) followers: Arc<Mutex<HashSet<(String, String)>>>,
    /// Serialises dashboard actions (apply, promote) from mirror fetch to recorded result, so
    /// the last press always records the newest channel head.
    pub(crate) actions: Arc<tokio::sync::Mutex<()>>,
    /// Demo mode (simulated fleet); reported in the snapshot.
    pub demo: bool,
}

impl AppState {
    pub fn new(
        cfg: Arc<ServerConfig>,
        db: DatabaseConnection,
        mirror: Arc<Mirror>,
        online: Arc<dyn OnlineProvider>,
        hosts: Vec<FleetHost>,
    ) -> anyhow::Result<Self> {
        let (tx, _) = broadcast::channel(BROADCAST_CAPACITY);
        Ok(Self {
            db,
            mirror,
            online,
            client: AgentClient::new()?,
            hosts,
            tx,
            cfg,
            reachable: Arc::default(),
            followers: Arc::default(),
            actions: Arc::default(),
            demo: false,
        })
    }

    /// Sends to dashboard clients; having none is fine.
    pub fn broadcast(&self, msg: WsMessage) {
        let _ = self.tx.send(msg);
    }
}

pub async fn host_view(state: &AppState, host: &FleetHost) -> HostView {
    let peers = state.online.peers().await;
    host_view_with(state, host, &peers).await
}

/// `host_view` with a `peers()` result the caller already has.
pub(crate) async fn host_view_with(
    state: &AppState,
    host: &FleetHost,
    peers: &HashMap<String, PeerInfo>,
) -> HostView {
    let peer = peers.get(&host.name.to_lowercase());
    let online = match peer {
        Some(p) if p.online => {
            let ok = state.reachable.lock().unwrap().get(&host.name).copied();
            if ok == Some(true) {
                OnlineState::On
            } else {
                OnlineState::AgentUnreachable
            }
        }
        _ => OnlineState::Off,
    };
    let stored = db::load_status(&state.db, &host.name)
        .await
        .unwrap_or_else(|e| {
            eprintln!("fleet-server: loading status of {}: {e:#}", host.name);
            None
        });
    let (status, last_ok_at) = match stored {
        Some((s, at)) => (Some(s), at),
        None => (None, None),
    };
    let behind = match &status {
        Some(s) => state.mirror.behind_count(&s.running, &host.channel).await,
        None => None,
    };
    let desired_apply_id = db::desired(&state.db, &host.name)
        .await
        .ok()
        .flatten()
        .map(|d| d.apply_id);
    let last_activation = db::last_audit(&state.db, &host.name, "activation")
        .await
        .ok()
        .flatten()
        .and_then(|a| serde_json::from_value::<ActivationEvent>(a.details).ok());
    HostView {
        name: host.name.clone(),
        os: host.os.clone(),
        channel: host.channel.clone(),
        online,
        last_seen: peer.and_then(|p| p.last_seen).or(last_ok_at),
        running_dirty: status
            .as_ref()
            .is_some_and(|s| s.running.ends_with("-dirty")),
        running: status.as_ref().map(|s| s.running.clone()),
        behind,
        checkout: status.as_ref().map(|s| s.checkout.clone()),
        last_apply: status.and_then(|s| s.apply),
        desired_apply_id,
        last_activation,
    }
}

/// One view per channel used by a fleet host, sorted by name.
pub async fn channels(state: &AppState) -> Vec<ChannelView> {
    let names: BTreeSet<&str> = state.hosts.iter().map(|h| h.channel.as_str()).collect();
    join_all(names.into_iter().map(|name| async move {
        let head = state.mirror.head(name).await;
        let head_subject = match &head {
            Some(c) => state.mirror.subject(c).await,
            None => None,
        };
        ChannelView {
            name: name.to_string(),
            head,
            head_subject,
        }
    }))
    .await
}

pub async fn snapshot(state: &AppState, viewer: String) -> Snapshot {
    let peers = state.online.peers().await;
    let hosts = join_all(state.hosts.iter().map(|h| host_view_with(state, h, &peers))).await;
    Snapshot {
        hosts,
        channels: channels(state).await,
        promote_candidate: state.mirror.promote_candidate().await,
        viewer,
        demo: state.demo,
    }
}
