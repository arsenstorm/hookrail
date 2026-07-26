//! Token storage: environment variable first, then the OS keychain.
//!
//! Tokens are never written to a file.

use anyhow::{anyhow, Context, Result};

const SERVICE: &str = "hookrail";
const ENV_TOKEN: &str = "HOOKRAIL_API_KEY";

pub const NOT_LOGGED_IN: &str = "Not logged in. Run `hookrail login` (or set HOOKRAIL_API_KEY).";

/// Keychain account for a server: the host, plus the port when non-default.
pub fn account(server: &str) -> Result<String> {
    let url = url::Url::parse(server).with_context(|| format!("invalid server URL: {server}"))?;
    let host = url
        .host_str()
        .ok_or_else(|| anyhow!("server URL has no host: {server}"))?;
    Ok(match url.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.to_string(),
    })
}

fn entry(server: &str) -> Result<keyring::Entry> {
    Ok(keyring::Entry::new(SERVICE, &account(server)?)?)
}

/// The token for `server`, if there is one. Keychain errors read as "no token".
pub fn load(server: &str) -> Option<String> {
    if let Ok(token) = std::env::var(ENV_TOKEN) {
        if !token.is_empty() {
            return Some(token);
        }
    }
    load_stored(server)
}

/// The keychain-stored token only — env credentials are not "stored".
pub fn load_stored(server: &str) -> Option<String> {
    let token = entry(server).ok()?.get_password().ok()?;
    (!token.is_empty()).then_some(token)
}

/// The note `logout` prints when an env credential outlives the stored one.
pub fn lingering_env_note() -> Option<&'static str> {
    let set = std::env::var_os(ENV_TOKEN).is_some_and(|v| !v.is_empty());
    set.then_some("note: HOOKRAIL_API_KEY is still set; unset it to stop authenticating with it.")
}

pub fn require(server: &str) -> Result<String> {
    load(server).ok_or_else(|| anyhow!(NOT_LOGGED_IN))
}

pub fn store(server: &str, token: &str) -> Result<()> {
    entry(server)
        .and_then(|e| Ok(e.set_password(token)?))
        .with_context(|| {
            "could not save the token to the OS keychain. On a headless machine, \
             set HOOKRAIL_API_KEY instead"
        })
}

/// Remove the stored token. Missing entries are not an error.
pub fn delete(server: &str) -> Result<()> {
    match entry(server)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::account;

    #[test]
    fn account_is_host_and_non_default_port() {
        assert_eq!(account("https://hookrail.dev").unwrap(), "hookrail.dev");
        assert_eq!(account("https://hookrail.dev/").unwrap(), "hookrail.dev");
        assert_eq!(account("http://localhost:3000").unwrap(), "localhost:3000");
    }

    #[test]
    fn account_rejects_garbage() {
        assert!(account("not a url").is_err());
    }

    /// The one test that touches HOOKRAIL_API_KEY, so it owns the variable.
    #[test]
    fn env_note_tracks_the_variable() {
        let restore = std::env::var_os(super::ENV_TOKEN);
        std::env::remove_var(super::ENV_TOKEN);
        assert_eq!(super::lingering_env_note(), None);
        std::env::set_var(super::ENV_TOKEN, "");
        assert_eq!(super::lingering_env_note(), None);
        std::env::set_var(super::ENV_TOKEN, "hkc_x");
        assert!(super::lingering_env_note().is_some());
        match restore {
            Some(value) => std::env::set_var(super::ENV_TOKEN, value),
            None => std::env::remove_var(super::ENV_TOKEN),
        }
    }
}
