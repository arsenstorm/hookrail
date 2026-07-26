//! Forward live webhooks to a local port over the cable connection.

use crate::api::{AttemptResult, Client};
use crate::cable::{self, Broadcast, Frame};
use crate::output::{body_excerpt, paint, status_color, truncate, BOLD, DIM, GREEN, RED, YELLOW};
use crate::{auth, commands};
use anyhow::{anyhow, bail, Result};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio_tungstenite::tungstenite::Message;

const BODY_EXCERPT_BYTES: usize = 10_000;
const LOCAL_TIMEOUT: Duration = Duration::from_secs(10);
const HEARTBEAT: Duration = Duration::from_secs(30);

struct Ctx {
    api: Client,
    local: reqwest::Client,
    token: String,
    origin: String,
    device: String,
    source_id: i64,
    port: u16,
    path_override: Option<String>,
}

enum Outcome {
    Rejected,
    /// Why the session ended, and whether it had ever been confirmed.
    Lost(String, bool),
}

pub async fn run(
    server: &str,
    port: u16,
    source: &str,
    path_override: Option<String>,
) -> Result<()> {
    let token = auth::require(server)?;
    let api = Client::new(server, Some(token.clone()))?;

    let sources = api.sources().await?;
    let matched = sources
        .iter()
        .find(|s| s.name.eq_ignore_ascii_case(source))
        .ok_or_else(|| {
            let names = sources
                .iter()
                .map(|s| s.name.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            if names.is_empty() {
                anyhow!("no source named \"{source}\". This organization has no sources yet.")
            } else {
                anyhow!("no source named \"{source}\". Available sources: {names}")
            }
        })?;

    let ctx = Arc::new(Ctx {
        api,
        local: reqwest::Client::builder().timeout(LOCAL_TIMEOUT).build()?,
        token,
        origin: origin(server)?,
        device: commands::hostname(),
        source_id: matched.id,
        port,
        path_override,
    });

    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            println!("\nStopped.");
            Ok(())
        }
        result = supervise(ctx) => result,
    }
}

/// Reconnect forever until the server rejects us (or Ctrl-C cancels this future).
async fn supervise(ctx: Arc<Ctx>) -> Result<()> {
    let mut failures = 0u32;
    let mut greeted = false;
    loop {
        let outcome = match session(&ctx, &mut greeted).await {
            Ok(outcome) => outcome,
            // A failed registration is as retryable as a dropped socket: the
            // usual cause of both is the server restarting under us.
            Err(e) => Outcome::Lost(format!("{e:#}"), false),
        };
        match outcome {
            Outcome::Rejected => {
                bail!("the server rejected this listener (was the connection deleted?)")
            }
            Outcome::Lost(why, was_connected) => {
                println!("{}", paint(DIM, &format!("reconnecting… ({why})")));
                // A session that worked earns a fresh backoff sequence.
                if was_connected {
                    failures = 0;
                }
                tokio::time::sleep(Duration::from_secs(cable::backoff(failures))).await;
                failures += 1;
            }
        }
    }
}

/// One listener registration plus the websocket session that follows it.
///
/// `greeted` tracks whether the opening banner has been printed yet, so a
/// server that is down at startup does not cost the user their banner.
async fn session(ctx: &Arc<Ctx>, greeted: &mut bool) -> Result<Outcome> {
    // find-or-create, so re-POSTing on every reconnect is safe.
    let listener = ctx.api.create_listener(ctx.source_id, &ctx.device).await?;

    let identifier = cable::identifier(
        &listener.subscription.channel,
        listener.subscription.connection_id,
    );
    let mut ws = cable::connect(&listener.websocket_url, &ctx.token, &ctx.origin).await?;
    ws.send(Message::Text(cable::subscribe_frame(&identifier)))
        .await?;

    let mut beat = tokio::time::interval(HEARTBEAT);
    beat.tick().await; // the first tick fires immediately
    let mut confirmed = false;

    loop {
        tokio::select! {
            _ = beat.tick() => {
                ws.send(Message::Text(cable::heartbeat_frame(&identifier))).await?;
            }
            frame = ws.next() => {
                let text = match frame {
                    Some(Ok(Message::Text(text))) => text,
                    Some(Ok(Message::Close(_))) | None => {
                        return Ok(Outcome::Lost("connection closed".into(), confirmed))
                    }
                    Some(Err(e)) => return Ok(Outcome::Lost(e.to_string(), confirmed)),
                    Some(Ok(_)) => continue,
                };
                match cable::parse(&text) {
                    Frame::Confirmed => {
                        confirmed = true;
                        if *greeted {
                            println!("{}", paint(GREEN, "connected"));
                        } else {
                            println!(
                                "{} → http://localhost:{}",
                                paint(BOLD, &listener.source.name),
                                ctx.port
                            );
                            println!("Waiting for events… (Ctrl-C to stop)");
                            *greeted = true;
                        }
                    }
                    Frame::Rejected => return Ok(Outcome::Rejected),
                    Frame::Disconnect => {
                        return Ok(Outcome::Lost("server closed the connection".into(), confirmed))
                    }
                    Frame::Event(broadcast) => {
                        // Forward off the socket loop so a slow endpoint cannot
                        // stall heartbeats or the next event.
                        tokio::spawn(forward(Arc::clone(ctx), *broadcast));
                    }
                    _ => {}
                }
            }
        }
    }
}

async fn forward(ctx: Arc<Ctx>, broadcast: Broadcast) {
    let forward = &broadcast.forward;
    let url = local_url(
        ctx.port,
        ctx.path_override.as_deref(),
        &forward.path,
        forward.query_string.as_deref(),
    );
    let method = reqwest::Method::from_bytes(forward.http_method.as_bytes())
        .unwrap_or(reqwest::Method::POST);

    let mut request = ctx.local.request(method, &url);
    for (name, value) in &forward.headers {
        // reqwest sets Host from the URL; forwarding the origin's would misroute.
        if !name.eq_ignore_ascii_case("host") {
            request = request.header(name, value);
        }
    }
    if let Some(body) = &forward.body {
        request = request.body(body.clone());
    }

    let started = Instant::now();
    let response = request.send().await;
    let (result, rendered) = match response {
        Ok(response) => {
            let status = response.status().as_u16();
            let bytes = response.bytes().await.unwrap_or_default();
            let duration_ms = started.elapsed().as_millis() as u64;
            (
                AttemptResult {
                    retry_count: broadcast.retry_count,
                    status: Some(status),
                    body_excerpt: Some(body_excerpt(&bytes, BODY_EXCERPT_BYTES)),
                    error: None,
                    duration_ms,
                },
                paint(status_color(status), &status.to_string()),
            )
        }
        Err(e) => {
            let duration_ms = started.elapsed().as_millis() as u64;
            let reason = short_error(&e);
            (
                AttemptResult {
                    retry_count: broadcast.retry_count,
                    status: None,
                    body_excerpt: None,
                    error: Some(reason.clone()),
                    duration_ms,
                },
                paint(RED, &format!("ERR {reason}")),
            )
        }
    };

    println!(
        "{}  {:<6} {:<30} → {} {}",
        paint(DIM, &chrono::Local::now().format("%H:%M:%S").to_string()),
        forward.http_method,
        truncate(&forward.path, 30),
        rendered,
        paint(DIM, &format!("({}ms)", result.duration_ms)),
    );

    if let Err(e) = ctx.api.report_result(broadcast.attempt_id, &result).await {
        eprintln!(
            "{} could not report attempt {}: {e:#}",
            paint(YELLOW, "warning:"),
            broadcast.attempt_id
        );
    }
}

/// The local URL an event is replayed to.
pub fn local_url(
    port: u16,
    path_override: Option<&str>,
    path: &str,
    query: Option<&str>,
) -> String {
    let path = path_override.unwrap_or(path);
    let mut url = format!("http://127.0.0.1:{port}{path}");
    match query {
        Some(query) if !query.is_empty() => {
            url.push('?');
            url.push_str(query);
        }
        _ => {}
    }
    url
}

/// "connect: Connection refused (os error 61)" — kind plus the innermost cause.
fn short_error(e: &reqwest::Error) -> String {
    let kind = if e.is_timeout() {
        "timeout"
    } else if e.is_connect() {
        "connect"
    } else if e.is_redirect() {
        "redirect"
    } else if e.is_body() || e.is_decode() {
        "body"
    } else {
        "request"
    };
    let mut cause: &dyn std::error::Error = e;
    while let Some(source) = cause.source() {
        cause = source;
    }
    format!("{kind}: {cause}")
}

fn origin(server: &str) -> Result<String> {
    Ok(url::Url::parse(server)?.origin().ascii_serialization())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_uses_the_forwarded_path() {
        assert_eq!(
            local_url(3000, None, "/wh", Some("a=1")),
            "http://127.0.0.1:3000/wh?a=1"
        );
    }

    #[test]
    fn url_override_replaces_the_path() {
        assert_eq!(
            local_url(4000, Some("/local"), "/wh", Some("a=1&b=2")),
            "http://127.0.0.1:4000/local?a=1&b=2"
        );
    }

    #[test]
    fn url_omits_empty_and_missing_query_strings() {
        assert_eq!(
            local_url(3000, None, "/wh", None),
            "http://127.0.0.1:3000/wh"
        );
        assert_eq!(
            local_url(3000, None, "/wh", Some("")),
            "http://127.0.0.1:3000/wh"
        );
    }

    #[test]
    fn origin_drops_the_path() {
        assert_eq!(
            origin("https://hookrail.dev").unwrap(),
            "https://hookrail.dev"
        );
        assert_eq!(
            origin("http://localhost:3000").unwrap(),
            "http://localhost:3000"
        );
    }
}
