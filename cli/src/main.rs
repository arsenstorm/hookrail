mod api;
mod auth;
mod cable;
mod commands;
mod output;

use api::EventFilters;
use clap::{Args, Parser, Subcommand};

const DEFAULT_SERVER: &str = "https://hookrail.dev";

#[derive(Parser)]
#[command(
    name = "hookrail",
    version,
    about = "Hookrail CLI — receive, inspect, and replay webhooks from your terminal."
)]
struct Cli {
    /// Hookrail server URL [env: HOOKRAIL_SERVER]
    #[arg(long, global = true, value_name = "URL")]
    server: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Authenticate this machine
    Login,
    /// Forget the stored credential
    Logout,
    /// Show who this credential belongs to
    Whoami,
    /// Forward live webhooks to a local port
    Listen {
        /// Local port to forward to
        port: u16,
        /// Source to listen on, by name
        #[arg(long)]
        source: String,
        /// Send every event to this path instead of the received one
        #[arg(long, value_name = "PATH")]
        path: Option<String>,
    },
    /// Inspect received webhooks
    Events {
        #[command(subcommand)]
        command: EventsCommand,
    },
    /// Re-enqueue a failed delivery
    Retry {
        /// Event to retry
        event_id: i64,
        /// Connection to redeliver to
        #[arg(long, value_name = "ID")]
        connection: Option<i64>,
    },
}

#[derive(Subcommand)]
enum EventsCommand {
    /// List recent events
    List {
        #[command(flatten)]
        filters: Filters,
        /// How many events to show (max 50)
        #[arg(long, value_name = "N", default_value_t = 20)]
        limit: usize,
    },
    /// Follow events as they arrive
    Tail {
        #[command(flatten)]
        filters: Filters,
    },
}

#[derive(Args)]
struct Filters {
    /// delivered, failed, partial, pending, undelivered or duplicate
    #[arg(long, value_name = "S")]
    status: Option<String>,
    /// Only events on this source
    #[arg(long, value_name = "N")]
    source_id: Option<i64>,
    /// Substring match on the event body
    #[arg(long, value_name = "TEXT")]
    q: Option<String>,
    /// Inclusive lower bound, e.g. 2026-07-01
    #[arg(long, value_name = "D")]
    from: Option<String>,
    /// Inclusive upper bound
    #[arg(long, value_name = "D")]
    to: Option<String>,
}

impl From<Filters> for EventFilters {
    fn from(f: Filters) -> Self {
        EventFilters {
            status: f.status,
            source_id: f.source_id,
            q: f.q,
            from: f.from,
            to: f.to,
        }
    }
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let server = resolve_server(cli.server);

    if let Err(e) = run(cli.command, &server).await {
        eprintln!("{} {e:#}", output::paint(output::RED, "error:"));
        std::process::exit(1);
    }
}

async fn run(command: Command, server: &str) -> anyhow::Result<()> {
    // Checked up front so a typo'd --server reports itself, rather than
    // surfacing later as a confusing "not logged in" or builder error.
    anyhow::ensure!(
        url::Url::parse(server).is_ok_and(|u| u.has_host()),
        "invalid server URL: {server}"
    );
    match command {
        Command::Login => commands::login::login(server).await,
        Command::Logout => commands::login::logout(server).await,
        Command::Whoami => commands::login::whoami(server).await,
        Command::Listen { port, source, path } => {
            commands::listen::run(server, port, &source, path).await
        }
        Command::Events { command } => match command {
            EventsCommand::List { filters, limit } => {
                commands::events::list(server, filters.into(), limit).await
            }
            EventsCommand::Tail { filters } => commands::events::tail(server, filters.into()).await,
        },
        Command::Retry {
            event_id,
            connection,
        } => commands::retry::run(server, event_id, connection).await,
    }
}

/// --server, then HOOKRAIL_SERVER, then the hosted default.
fn resolve_server(flag: Option<String>) -> String {
    let server = flag
        .or_else(|| std::env::var("HOOKRAIL_SERVER").ok())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_SERVER.to_string());
    server.trim_end_matches('/').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn server_falls_back_to_the_hosted_default() {
        if std::env::var_os("HOOKRAIL_SERVER").is_none() {
            assert_eq!(resolve_server(None), DEFAULT_SERVER);
        }
    }

    #[test]
    fn server_flag_wins_and_loses_its_trailing_slash() {
        assert_eq!(
            resolve_server(Some("http://localhost:3000/".into())),
            "http://localhost:3000"
        );
    }

    #[test]
    fn cli_parses() {
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }
}
