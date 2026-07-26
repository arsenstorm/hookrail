//! Action Cable protocol: frame parsing, subscription identifiers, reconnect backoff.

use anyhow::Result;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};

pub type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// What arrived on the socket.
#[derive(Debug, PartialEq)]
pub enum Frame {
    Welcome,
    Ping,
    Confirmed,
    Rejected,
    Disconnect,
    Event(Box<Broadcast>),
    /// Anything we do not act on.
    Other,
}

#[derive(Debug, Deserialize, PartialEq)]
pub struct Broadcast {
    pub attempt_id: i64,
    pub retry_count: i64,
    pub event_id: i64,
    pub forward: Forward,
}

#[derive(Debug, Deserialize, PartialEq)]
pub struct Forward {
    pub http_method: String,
    pub path: String,
    #[serde(default)]
    pub query_string: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default)]
    pub body: Option<String>,
}

/// Classify one text frame. Unparseable frames are `Other`, never an error —
/// an unknown frame is not worth tearing down a working connection.
pub fn parse(raw: &str) -> Frame {
    let Ok(value) = serde_json::from_str::<Value>(raw) else {
        return Frame::Other;
    };
    if let Some(kind) = value.get("type").and_then(Value::as_str) {
        return match kind {
            "welcome" => Frame::Welcome,
            "ping" => Frame::Ping,
            "confirm_subscription" => Frame::Confirmed,
            "reject_subscription" => Frame::Rejected,
            "disconnect" => Frame::Disconnect,
            _ => Frame::Other,
        };
    }
    match value.get("message") {
        Some(message) => serde_json::from_value(message.clone())
            .map(|b| Frame::Event(Box::new(b)))
            .unwrap_or(Frame::Other),
        None => Frame::Other,
    }
}

/// The subscription identifier: a JSON *string* containing JSON.
pub fn identifier(channel: &str, connection_id: i64) -> String {
    json!({ "channel": channel, "connection_id": connection_id }).to_string()
}

pub fn subscribe_frame(identifier: &str) -> String {
    json!({ "command": "subscribe", "identifier": identifier }).to_string()
}

pub fn heartbeat_frame(identifier: &str) -> String {
    json!({
        "command": "message",
        "identifier": identifier,
        "data": r#"{"action":"heartbeat"}"#,
    })
    .to_string()
}

/// Reconnect delay in seconds: 1, 2, 4, 8, 16, then 30 forever.
pub fn backoff(attempt: u32) -> u64 {
    2u64.saturating_pow(attempt).min(30)
}

pub async fn connect(ws_url: &str, token: &str, origin: &str) -> Result<Socket> {
    let mut request = ws_url.into_client_request()?;
    let headers = request.headers_mut();
    headers.insert("Authorization", format!("Bearer {token}").parse()?);
    headers.insert("Origin", origin.parse()?);
    Ok(connect_async(request).await?.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_control_frames() {
        assert_eq!(parse(r#"{"type":"welcome"}"#), Frame::Welcome);
        assert_eq!(
            parse(r#"{"type":"ping","message":1769000000}"#),
            Frame::Ping
        );
        assert_eq!(
            parse(r#"{"type":"confirm_subscription","identifier":"{}"}"#),
            Frame::Confirmed
        );
        assert_eq!(
            parse(r#"{"type":"reject_subscription","identifier":"{}"}"#),
            Frame::Rejected
        );
        assert_eq!(
            parse(r#"{"type":"disconnect","reason":"x"}"#),
            Frame::Disconnect
        );
        assert_eq!(parse(r#"{"type":"something_new"}"#), Frame::Other);
    }

    #[test]
    fn parses_a_broadcast() {
        let raw = r#"{"identifier":"{\"channel\":\"CliChannel\",\"connection_id\":7}",
          "message":{"attempt_id":91,"retry_count":2,"event_id":4021,
          "forward":{"http_method":"POST","path":"/wh","query_string":"a=1",
          "headers":{"Content-Type":"application/json","Host":"hookrail.dev"},
          "body":"{\"hello\":\"world\"}"}}}"#;
        let Frame::Event(b) = parse(raw) else {
            panic!("expected an event frame");
        };
        assert_eq!(b.attempt_id, 91);
        assert_eq!(b.retry_count, 2);
        assert_eq!(b.event_id, 4021);
        assert_eq!(b.forward.http_method, "POST");
        assert_eq!(b.forward.path, "/wh");
        assert_eq!(b.forward.query_string.as_deref(), Some("a=1"));
        assert_eq!(b.forward.headers.len(), 2);
        assert_eq!(b.forward.body.as_deref(), Some(r#"{"hello":"world"}"#));
    }

    #[test]
    fn broadcast_tolerates_null_query_string_and_body() {
        let raw = r#"{"identifier":"x","message":{"attempt_id":1,"retry_count":0,"event_id":2,
          "forward":{"http_method":"GET","path":"/","query_string":null,"headers":{},"body":null}}}"#;
        let Frame::Event(b) = parse(raw) else {
            panic!("expected an event frame");
        };
        assert_eq!(b.forward.query_string, None);
        assert_eq!(b.forward.body, None);
    }

    #[test]
    fn garbage_is_other() {
        assert_eq!(parse("not json"), Frame::Other);
        assert_eq!(parse(r#"{"message":{"nope":true}}"#), Frame::Other);
    }

    #[test]
    fn identifier_is_double_encoded() {
        let id = identifier("CliChannel", 7);
        assert_eq!(id, r#"{"channel":"CliChannel","connection_id":7}"#);

        // The subscribe frame carries it as a string, not a nested object.
        let frame: Value = serde_json::from_str(&subscribe_frame(&id)).unwrap();
        assert_eq!(frame["command"], "subscribe");
        let inner = frame["identifier"]
            .as_str()
            .expect("identifier is a string");
        let decoded: Value = serde_json::from_str(inner).unwrap();
        assert_eq!(decoded["channel"], "CliChannel");
        assert_eq!(decoded["connection_id"], 7);
    }

    #[test]
    fn heartbeat_data_is_a_json_string() {
        let frame: Value = serde_json::from_str(&heartbeat_frame("id")).unwrap();
        assert_eq!(frame["command"], "message");
        assert_eq!(frame["identifier"], "id");
        let data: Value = serde_json::from_str(frame["data"].as_str().unwrap()).unwrap();
        assert_eq!(data["action"], "heartbeat");
    }

    #[test]
    fn backoff_doubles_then_caps_at_30() {
        let seq: Vec<u64> = (0..10).map(backoff).collect();
        assert_eq!(seq, vec![1, 2, 4, 8, 16, 30, 30, 30, 30, 30]);
        assert_eq!(backoff(u32::MAX), 30);
    }
}
