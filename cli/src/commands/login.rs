//! login / logout / whoami — everything that touches the stored credential.

use crate::api::{Client, DevicePoll, TokenInfo};
use crate::auth;
use crate::output::{paint, BOLD, DIM, GREEN};
use anyhow::{bail, Result};
use std::io::Write;
use std::time::{Duration, Instant};

pub async fn login(server: &str) -> Result<()> {
    let client = Client::new(server, None)?;
    let auth_request = client.device_authorize(&super::hostname()).await?;

    println!(
        "First, copy your one-time code: {}",
        paint(BOLD, &auth_request.user_code)
    );
    print!(
        "Press Enter to open {} in your browser… ",
        auth_request.verification_url
    );
    std::io::stdout().flush()?;
    read_line().await?;

    if open::that(&auth_request.verification_url).is_err() {
        println!("Open this URL: {}", auth_request.verification_url);
    }

    let deadline = Instant::now() + Duration::from_secs(auth_request.expires_in);
    let interval = Duration::from_secs(auth_request.interval.max(1));
    let grant = loop {
        tokio::time::sleep(interval).await;
        if Instant::now() >= deadline {
            bail!("Login timed out. Run `hookrail login` again.");
        }
        match client.device_token(&auth_request.device_code).await? {
            DevicePoll::Pending => continue,
            DevicePoll::Granted(grant) => break grant,
        }
    };

    auth::store(server, &grant.token)?;
    println!(
        "{} Logged in to {}",
        paint(GREEN, "✓"),
        grant.organization.name
    );
    Ok(())
}

/// Wait for Enter without blocking the runtime.
async fn read_line() -> Result<()> {
    tokio::task::spawn_blocking(|| std::io::stdin().read_line(&mut String::new())).await??;
    Ok(())
}

pub async fn logout(server: &str) -> Result<()> {
    // Only the keychain entry: an env credential is the user's to unset.
    if let Some(token) = auth::load_stored(server) {
        if token.starts_with("hkc_") {
            // Best effort: a revoked or unreachable token still gets forgotten locally.
            if let Ok(client) = Client::new(server, Some(token)) {
                let _ = client.revoke_token().await;
            }
        }
    }
    auth::delete(server)?;
    println!("Logged out.");
    if let Some(note) = auth::lingering_env_note() {
        println!("{}", paint(DIM, note));
    }
    Ok(())
}

pub async fn whoami(server: &str) -> Result<()> {
    let who = super::client(server)?.whoami().await?;

    let user = match &who.user {
        Some(user) => match (&user.github_login, &user.name) {
            (Some(login), Some(name)) => format!("{login} ({name})"),
            (Some(login), None) => login.clone(),
            (None, Some(name)) => name.clone(),
            (None, None) => "unknown".to_string(),
        },
        None => "org API key".to_string(),
    };
    let token = match &who.token {
        TokenInfo::Cli { prefix, name } => match name {
            Some(name) => format!("cli {prefix} ({name})"),
            None => format!("cli {prefix}"),
        },
        TokenInfo::ApiKey => "api key".to_string(),
    };

    for (label, value) in [
        ("User", user),
        ("Organization", who.organization.name),
        ("Token", token),
    ] {
        println!("{}  {value}", paint(DIM, &format!("{label:<12}")));
    }
    Ok(())
}
