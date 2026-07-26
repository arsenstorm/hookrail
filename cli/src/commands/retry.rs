//! `retry` — re-enqueue one delivery.

use crate::output::{paint, GREEN};
use anyhow::{bail, Result};

pub async fn run(server: &str, event_id: i64, connection: Option<i64>) -> Result<()> {
    let client = super::client(server)?;

    let connection_id = match connection {
        Some(id) => id,
        None => {
            let mut ids: Vec<i64> = client
                .attempts(event_id)
                .await?
                .iter()
                .map(|a| a.connection_id)
                .collect();
            ids.sort_unstable();
            ids.dedup();
            match ids.as_slice() {
                [] => bail!("No prior delivery attempts; specify --connection."),
                [only] => *only,
                many => {
                    let list = many
                        .iter()
                        .map(|id| id.to_string())
                        .collect::<Vec<_>>()
                        .join(", ");
                    bail!("This event was delivered to several connections ({list}). Pick one with --connection.")
                }
            }
        }
    };

    client.retry(event_id, connection_id).await?;
    println!("{} Retry queued.", paint(GREEN, "✓"));
    Ok(())
}
