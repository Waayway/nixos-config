use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;

use anyhow::Context;
use clap::Parser;
use fleet_server::config::{ServerConfig, load_hosts};
use fleet_server::mirror::Mirror;
use fleet_server::state::AppState;
use fleet_server::{api, db, poller, tailscale};

#[derive(Parser)]
#[command(name = "fleet-server", version)]
struct Cli {
    /// Server configuration (JSON).
    #[arg(long)]
    config: PathBuf,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let result = tokio::runtime::Runtime::new()
        .context("starting the tokio runtime")
        .and_then(|rt| rt.block_on(run(cli)));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fleet-server: {e:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run(cli: Cli) -> anyhow::Result<()> {
    let cfg = ServerConfig::load(&cli.config)?;
    cfg.check_listen()?;
    let hosts = load_hosts(&cfg.hosts_file)?;
    let conn = db::connect(&cfg.state_dir).await?;
    let mirror = Arc::new(Mirror::open_or_init(&cfg).await?);
    let online = tailscale::provider_from_config(&cfg.online, &cfg.tailscale_bin)?;
    let listen = cfg.listen;
    let state = AppState::new(Arc::new(cfg), conn, mirror, online, hosts)?;
    poller::spawn(state.clone());
    let listener = tokio::net::TcpListener::bind(listen)
        .await
        .with_context(|| format!("binding {listen}"))?;
    eprintln!("fleet-server: listening on {listen}");
    axum::serve(
        listener,
        api::app(state).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .context("serving")
}
