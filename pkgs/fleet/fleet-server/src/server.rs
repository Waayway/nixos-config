//! Server bootstrap shared by `fleet-server serve` and `fleet-server demo`: database, git
//! mirror, poller and the dashboard listener.

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use tokio::task::JoinHandle;

use crate::config::{FleetHost, ServerConfig};
use crate::mirror::Mirror;
use crate::state::AppState;
use crate::tailscale::OnlineProvider;
use crate::{api, db, poller};

/// A running server. Dropping it stops the listener and the poller.
pub struct ServerHandle {
    /// The address actually bound (useful with port 0).
    pub addr: SocketAddr,
    pub state: AppState,
    serve: JoinHandle<std::io::Result<()>>,
    background: Vec<JoinHandle<()>>,
}

impl ServerHandle {
    /// Serves until the listener fails. Dropping this future (and the handle) still stops
    /// the server.
    pub async fn wait(mut self) -> anyhow::Result<()> {
        (&mut self.serve)
            .await
            .context("server task")?
            .context("serving")
    }
}

impl Drop for ServerHandle {
    fn drop(&mut self) {
        self.serve.abort();
        for t in &self.background {
            t.abort();
        }
    }
}

/// Starts the server and returns once it is listening on `cfg.listen`.
pub async fn start(
    cfg: ServerConfig,
    hosts: Vec<FleetHost>,
    online: Arc<dyn OnlineProvider>,
    demo: bool,
) -> anyhow::Result<ServerHandle> {
    cfg.check_listen()?;
    let conn = db::connect(&cfg.state_dir).await?;
    let mirror = Arc::new(Mirror::open_or_init(&cfg).await?);
    let listen = cfg.listen;
    let mut state = AppState::new(Arc::new(cfg), conn, mirror, online, hosts)?;
    state.demo = demo;
    let listener = tokio::net::TcpListener::bind(listen)
        .await
        .with_context(|| format!("binding {listen}"))?;
    let addr = listener.local_addr().context("listener address")?;
    let background = poller::spawn(state.clone());
    let app = api::app(state.clone()).into_make_service_with_connect_info::<SocketAddr>();
    let serve = tokio::spawn(async move { axum::serve(listener, app).await });
    eprintln!("fleet-server: listening on {addr}");
    Ok(ServerHandle {
        addr,
        state,
        serve,
        background,
    })
}
