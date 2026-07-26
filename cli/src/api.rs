//! HTTP client for the Hookrail API, plus the JSON shapes it exchanges.

use anyhow::{anyhow, Context, Result};
use reqwest::{Method, RequestBuilder, Response, StatusCode};
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub struct Client {
    http: reqwest::Client,
    server: String,
    token: Option<String>,
}

impl Client {
    pub fn new(server: &str, token: Option<String>) -> Result<Self> {
        Ok(Self {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(30))
                .build()?,
            server: server.trim_end_matches('/').to_string(),
            token,
        })
    }

    fn request(&self, method: Method, path: &str) -> RequestBuilder {
        let rb = self.http.request(method, format!("{}{path}", self.server));
        match &self.token {
            Some(token) => rb.bearer_auth(token),
            None => rb,
        }
    }

    /// Send a request, mapping transport failures and error envelopes to `Err`.
    async fn send(&self, rb: RequestBuilder) -> Result<Response> {
        let resp = self.raw(rb).await?;
        if resp.status().is_success() {
            Ok(resp)
        } else {
            Err(api_error(resp).await)
        }
    }

    /// Send a request without inspecting the status code.
    async fn raw(&self, rb: RequestBuilder) -> Result<Response> {
        rb.send()
            .await
            .with_context(|| format!("could not reach {}", self.server))
    }

    pub async fn sources(&self) -> Result<Vec<Source>> {
        let resp = self
            .send(self.request(Method::GET, "/api/v1/sources"))
            .await?;
        Ok(resp.json::<SourcesEnvelope>().await?.sources)
    }

    pub async fn whoami(&self) -> Result<Whoami> {
        let resp = self
            .send(self.request(Method::GET, "/api/v1/cli/whoami"))
            .await?;
        Ok(resp.json().await?)
    }

    pub async fn revoke_token(&self) -> Result<()> {
        self.send(self.request(Method::DELETE, "/api/v1/cli/token"))
            .await?;
        Ok(())
    }

    pub async fn create_listener(&self, source_id: i64, device_name: &str) -> Result<Listener> {
        let resp =
            self.send(self.request(Method::POST, "/api/v1/cli/listeners").json(
                &serde_json::json!({
                    "source": source_id,
                    "device_name": device_name,
                }),
            ))
            .await?;
        Ok(resp.json().await?)
    }

    /// Report a forwarded delivery back to the server.
    pub async fn report_result(&self, attempt_id: i64, result: &AttemptResult) -> Result<()> {
        let path = format!("/api/v1/cli/attempts/{attempt_id}/result");
        self.send(self.request(Method::POST, &path).json(result))
            .await?;
        Ok(())
    }

    pub async fn events(&self, filters: &EventFilters) -> Result<Vec<Event>> {
        let resp = self
            .send(
                self.request(Method::GET, "/api/v1/events")
                    .query(&filters.pairs()),
            )
            .await?;
        Ok(resp.json::<EventsPage>().await?.events)
    }

    pub async fn attempts(&self, event_id: i64) -> Result<Vec<Attempt>> {
        let path = format!("/api/v1/events/{event_id}/attempts");
        let resp = self.send(self.request(Method::GET, &path)).await?;
        Ok(resp.json::<AttemptsEnvelope>().await?.attempts)
    }

    pub async fn retry(&self, event_id: i64, connection_id: i64) -> Result<()> {
        let path = format!("/api/v1/events/{event_id}/retries");
        self.send(
            self.request(Method::POST, &path)
                .json(&serde_json::json!({ "connection_id": connection_id })),
        )
        .await?;
        Ok(())
    }

    pub async fn device_authorize(&self, device_name: &str) -> Result<DeviceAuth> {
        let resp = self
            .send(
                self.request(Method::POST, "/api/v1/cli/device_authorizations")
                    .json(&serde_json::json!({ "device_name": device_name })),
            )
            .await?;
        Ok(resp.json().await?)
    }

    pub async fn device_token(&self, device_code: &str) -> Result<DevicePoll> {
        let resp = self
            .raw(
                self.request(Method::POST, "/api/v1/cli/device_authorizations/token")
                    .json(&serde_json::json!({ "device_code": device_code })),
            )
            .await?;
        match resp.status() {
            StatusCode::ACCEPTED => Ok(DevicePoll::Pending),
            s if s.is_success() => Ok(DevicePoll::Granted(resp.json().await?)),
            _ => Err(api_error(resp).await),
        }
    }
}

async fn api_error(resp: Response) -> anyhow::Error {
    let status = resp.status();
    if status == StatusCode::UNAUTHORIZED {
        return anyhow!("Not logged in (or the token was revoked). Run `hookrail login`.");
    }
    let body = resp.text().await.unwrap_or_default();
    match serde_json::from_str::<ErrorEnvelope>(&body) {
        Ok(e) => anyhow!("{}", e.error.message),
        Err(_) => anyhow!("the server returned HTTP {}", status.as_u16()),
    }
}

#[derive(Deserialize)]
struct ErrorEnvelope {
    error: ApiError,
}

#[derive(Deserialize)]
struct ApiError {
    message: String,
}

#[derive(Deserialize)]
struct SourcesEnvelope {
    sources: Vec<Source>,
}

#[derive(Deserialize)]
pub struct Source {
    pub id: i64,
    pub name: String,
}

#[derive(Deserialize)]
pub struct Organization {
    pub name: String,
}

#[derive(Deserialize)]
pub struct User {
    pub github_login: Option<String>,
    pub name: Option<String>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TokenInfo {
    Cli {
        prefix: String,
        name: Option<String>,
    },
    ApiKey,
}

#[derive(Deserialize)]
pub struct Whoami {
    pub user: Option<User>,
    pub organization: Organization,
    pub token: TokenInfo,
}

#[derive(Deserialize)]
pub struct DeviceAuth {
    pub device_code: String,
    pub user_code: String,
    pub verification_url: String,
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Deserialize)]
pub struct DeviceGrant {
    pub token: String,
    pub organization: Organization,
}

pub enum DevicePoll {
    Pending,
    Granted(DeviceGrant),
}

#[derive(Deserialize)]
pub struct Listener {
    pub source: Source,
    pub websocket_url: String,
    pub subscription: Subscription,
}

#[derive(Deserialize)]
pub struct Subscription {
    pub channel: String,
    pub connection_id: i64,
}

#[derive(Serialize)]
pub struct AttemptResult {
    pub retry_count: i64,
    pub status: Option<u16>,
    pub body_excerpt: Option<String>,
    pub error: Option<String>,
    pub duration_ms: u64,
}

#[derive(Deserialize)]
struct EventsPage {
    events: Vec<Event>,
}

#[derive(Deserialize)]
pub struct Event {
    pub id: i64,
    pub http_method: String,
    pub path: String,
    pub received_at: String,
}

#[derive(Deserialize)]
struct AttemptsEnvelope {
    attempts: Vec<Attempt>,
}

#[derive(Deserialize)]
pub struct Attempt {
    pub connection_id: i64,
}

/// Filters shared by `events list` and `events tail`.
#[derive(Default)]
pub struct EventFilters {
    pub status: Option<String>,
    pub source_id: Option<i64>,
    pub q: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
}

impl EventFilters {
    fn pairs(&self) -> Vec<(&'static str, String)> {
        let mut out = Vec::new();
        let mut push = |k, v: Option<String>| {
            if let Some(v) = v {
                out.push((k, v));
            }
        };
        push("status", self.status.clone());
        push("source_id", self.source_id.map(|id| id.to_string()));
        push("q", self.q.clone());
        push("from", self.from.clone());
        push("to", self.to.clone());
        out
    }
}
