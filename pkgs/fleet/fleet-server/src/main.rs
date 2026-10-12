use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::Context;
use clap::{Parser, Subcommand};
use fleet_server::config::{ServerConfig, load_hosts};
use fleet_server::{demo, server, tailscale};

#[derive(Parser)]
#[command(name = "fleet-server", version, args_conflicts_with_subcommands = true)]
struct Cli {
    /// Server configuration (JSON); same as `fleet-server serve --config`.
    #[arg(long)]
    config: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Runs the fleet server.
    Serve {
        /// Server configuration (JSON).
        #[arg(long)]
        config: PathBuf,
    },
    /// Runs the real server and dashboard against a simulated fleet.
    Demo {
        /// Dashboard address. Access control is off in demo mode.
        #[arg(long, default_value = "127.0.0.1:8080")]
        listen: SocketAddr,
        /// Time multiplier for the simulation (applies, polling, new commits).
        #[arg(long, default_value_t = 1.0)]
        speed: f64,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let command = match (cli.command, cli.config) {
        (Some(c), _) => c,
        (None, Some(config)) => Command::Serve { config },
        (None, None) => {
            eprintln!("fleet-server: give --config <path>, or a subcommand (see --help)");
            return ExitCode::from(2);
        }
    };
    let result = tokio::runtime::Runtime::new()
        .context("starting the tokio runtime")
        .and_then(|rt| rt.block_on(run(command)));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fleet-server: {e:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run(command: Command) -> anyhow::Result<()> {
    match command {
        Command::Serve { config } => {
            let cfg = ServerConfig::load(&config)?;
            let hosts = load_hosts(&cfg.hosts_file)?;
            let online = tailscale::provider_from_config(&cfg.online, &cfg.tailscale_bin)?;
            server::start(cfg, hosts, online, false).await?.wait().await
        }
        Command::Demo { listen, speed } => {
            let handle = demo::start(listen, speed).await?;
            eprintln!("fleet-server: demo dashboard at http://{}/", handle.addr);
            // On Ctrl-C the handle is dropped, which stops the demo and removes its temp dir.
            tokio::select! {
                r = handle.wait() => r,
                r = tokio::signal::ctrl_c() => r.context("waiting for Ctrl-C"),
            }
        }
    }
}
