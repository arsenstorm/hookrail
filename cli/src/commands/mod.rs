pub mod events;
pub mod listen;
pub mod login;
pub mod retry;

use crate::{api::Client, auth};
use anyhow::Result;

/// An authenticated client, or the "not logged in" error.
pub fn client(server: &str) -> Result<Client> {
    Client::new(server, Some(auth::require(server)?))
}

pub fn hostname() -> String {
    gethostname::gethostname().to_string_lossy().into_owned()
}
