use clap::Parser;
use fleetctl::{Cli, Client};

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let client = Client::new(&cli.server);
    let code = match fleetctl::run(&client, cli.command, &mut std::io::stdout()).await {
        Ok(code) => code,
        Err(e) => {
            eprintln!("fleetctl: {e:#}");
            2
        }
    };
    std::process::exit(code);
}
