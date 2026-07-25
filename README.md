# Hookrail

Webhook gateway: receive, inspect, and forward webhooks.

## Stack
- Rails 8.1 (Ruby 3.3.5), Hotwire (Turbo + Stimulus), Tailwind v4
- Postgres
- Solid Queue for background jobs
- Docker for deploy

## Dev setup
```sh
bin/setup          # installs deps, prepares db
bin/dev            # runs web + tailwind watcher
```
App boots at http://localhost:3000, health check at `/up`.

## Inbound signature verification

Each source can verify the HMAC signature on incoming webhooks. Configure it on the source's edit page.
Requests that fail verification are rejected with `401` and stored in **Quarantine** (`/quarantine`) so you can
inspect the headers and body. Leaving the signing secret blank disables verification for that source.

| Field | Meaning |
| --- | --- |
| Signing secret | Shared secret. Blank disables verification. |
| Signature header | Header carrying the signature. |
| Algorithm | `sha256` (default), `sha1`, `sha512`. |
| Encoding | `hex` (default) or `base64`. |
| Header format | `value` — whole header is the signature; `kv` — comma-separated `key=value` pairs. |
| Signature prefix | Stripped from the signature before comparing, e.g. `sha256=`. |
| Signature key | Key holding the signature when the format is `kv`. Default `v1`. |
| Timestamp key | Key holding the timestamp when the format is `kv`. |
| Timestamp header | Header holding the timestamp, when it is not in the signature header. |
| Payload template | What gets signed: `{body}` (default) or `{timestamp}.{body}`. |
| Tolerance (seconds) | Reject timestamps older than this. Blank skips the check. |

Signature in the whole header value (GitHub-style):

| Field | Value |
| --- | --- |
| Signature header | `X-Hub-Signature-256` |
| Header format | `value` |
| Signature prefix | `sha256=` |
| Algorithm / Encoding | `sha256` / `hex` |
| Payload template | `{body}` |

Signature in key=value pairs (Stripe-style):

| Field | Value |
| --- | --- |
| Signature header | `Stripe-Signature` |
| Header format | `kv` |
| Signature key | `v1` |
| Timestamp key | `t` |
| Algorithm / Encoding | `sha256` / `hex` |
| Payload template | `{timestamp}.{body}` |
| Tolerance | `300` |

## REST API

A JSON API under `/api/v1` covers sources, destinations, connections, events, delivery attempts, and retries.
Requests authenticate with an org-scoped bearer key: `Authorization: Bearer <key>`. Create and revoke keys in
the UI at `/api_keys` — the raw key is shown once and only its digest is stored.
Endpoint reference: [docs/api.md](docs/api.md).
