//! `events list` and `events tail`.

use crate::api::{Event, EventFilters};
use crate::output::{paint, table, truncate, DIM, YELLOW};
use anyhow::Result;
use std::time::Duration;

const MAX_LIMIT: usize = 50;
const PATH_WIDTH: usize = 40;

pub async fn list(server: &str, filters: EventFilters, limit: usize) -> Result<()> {
    let events = super::client(server)?.events(&filters).await?;
    let events = &events[..events.len().min(limit.clamp(1, MAX_LIMIT))];

    if events.is_empty() {
        println!("No events.");
        return Ok(());
    }

    let rows: Vec<Vec<String>> = events
        .iter()
        .map(|e| {
            vec![
                e.id.to_string(),
                local_time(&e.received_at),
                e.http_method.clone(),
                truncate(&e.path, PATH_WIDTH),
            ]
        })
        .collect();
    table(&["ID", "RECEIVED", "METHOD", "PATH"], &rows);
    Ok(())
}

pub async fn tail(server: &str, filters: EventFilters) -> Result<()> {
    let client = super::client(server)?;

    let recent = client.events(&filters).await?;
    for event in recent.iter().take(5).rev() {
        print_event(event);
    }
    let mut newest = recent.first().map(|e| e.id).unwrap_or(0);

    tokio::select! {
        _ = tokio::signal::ctrl_c() => Ok(()),
        result = async {
            loop {
                // ponytail: 3s polling; switch to the websocket feed if it matters
                tokio::time::sleep(Duration::from_secs(3)).await;
                match client.events(&filters).await {
                    Ok(batch) => {
                        for event in batch.iter().filter(|e| e.id > newest).rev() {
                            print_event(event);
                        }
                        if let Some(first) = batch.first() {
                            newest = newest.max(first.id);
                        }
                    }
                    // A blip should not end the tail; the next poll catches up.
                    Err(e) => eprintln!("{} {e:#}", paint(YELLOW, "warning:")),
                }
            }
        } => result,
    }
}

fn print_event(event: &Event) {
    println!(
        "{}  {:<6} {}  {}",
        paint(DIM, &local_time(&event.received_at)),
        event.http_method,
        truncate(&event.path, PATH_WIDTH),
        paint(DIM, &format!("#{}", event.id)),
    );
}

/// ISO 8601 from the API, rendered in the local timezone.
fn local_time(iso: &str) -> String {
    chrono::DateTime::parse_from_rfc3339(iso)
        .map(|t| {
            t.with_timezone(&chrono::Local)
                .format("%Y-%m-%d %H:%M:%S")
                .to_string()
        })
        .unwrap_or_else(|_| iso.to_string())
}

#[cfg(test)]
mod tests {
    use super::local_time;

    #[test]
    fn local_time_parses_iso8601() {
        // Rendering is timezone-dependent; the shape is not.
        let out = local_time("2026-07-25T15:07:29.657Z");
        assert_eq!(out.len(), 19, "{out}");
        assert!(out.starts_with("2026-07-2"), "{out}");
    }

    #[test]
    fn local_time_passes_through_unparseable_input() {
        assert_eq!(local_time("whenever"), "whenever");
    }
}
