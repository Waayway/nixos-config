use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use fleet_agent::{apply, config};
use fleet_proto::ApplyState;

#[derive(Parser)]
#[command(name = "fleet-agent", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run the agent daemon.
    Serve {
        #[arg(long)]
        config: PathBuf,
    },
    /// Run one apply (started by the daemon, outside its process).
    Apply {
        #[arg(long)]
        config: PathBuf,
        id: String,
        commit: String,
    },
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("fleet-agent: {e:#}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> anyhow::Result<ExitCode> {
    match cli.command {
        Command::Serve { config } => {
            config::load(&config)?;
            eprintln!("fleet-agent: serve is not implemented yet");
            Ok(ExitCode::FAILURE)
        }
        Command::Apply { config, id, commit } => {
            let cfg = config::load(&config)?;
            let rec = apply::run_apply(&cfg, &id, &commit);
            Ok(match rec.state {
                ApplyState::Ok | ApplyState::Skipped => ExitCode::SUCCESS,
                _ => ExitCode::FAILURE,
            })
        }
    }
}
