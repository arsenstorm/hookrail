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

## Routing rules

Each connection can filter which of its source's events it forwards. Edit the rule at *Connections → Edit rule*.
A connection with no rule receives everything; otherwise **all** criteria below must match (AND), and values are
compared as strings.

| Criterion | Meaning |
| --- | --- |
| Path | Request path the webhook arrived on. `*` is a glob wildcard, not regex: `/hooks/*` matches `/hooks/gh`. |
| Method | HTTP method, case-insensitive. Blank matches any method. |
| Headers | One `Name: value` per line. Names are case-insensitive, values must match exactly. |
| Body fields | One `dot.path=value` per line, addressing nested JSON: `data.object.status=succeeded`, `type=invoice.paid`. |

A body that is not a JSON object fails every body criterion — it never errors, it just doesn't match. Blank
criteria are dropped, so clearing all four restores "receives everything".

## Event replay

Replay re-sends events you have already received to one connection you choose — for backfilling a destination
that was down, misconfigured, or newly added. Filter the events list down to the set you want, pick a
connection, and hit *Replay*; the whole filtered set is replayed, not just the visible page.

Replayed deliveries carry `X-Hookrail-Replay: true` so the destination can tell them apart from first-time
traffic and dedupe on its own. Unlike a retry, a replay re-sends even events that already delivered
successfully — that is the point of it.

Two things are skipped, and the notice counts only what was actually enqueued:

- Events whose latest delivery on that connection is still in flight, so a replay can't race a delivery already underway.
- Events the connection's routing rule doesn't match — replay respects rules exactly as live delivery does.

Replay targets must be active connections — a paused or disabled connection refuses the whole replay.

The same operation is available over the API as `POST /api/v1/events/bulk_replay`.

## Pausing and disabling connections

Every connection is *active*, *paused*, or *disabled*. The buttons on the Connections page move it between
states, and the API exposes the same thing as the connection's `status`.

| State | Events | Deliveries |
| --- | --- | --- |
| Active | Received and stored | Attempted normally |
| Paused | Received and stored | Held, never sent |
| Disabled | Still ingested, visible on the source | Not created at all |

While a connection is paused, matched events still arrive and are stored, but their deliveries are held rather
than attempted: nothing is sent, nothing fails, no alerts fire. Resuming releases the held deliveries in the
order the events arrived.

While a connection is disabled, events keep being ingested and stay visible on the source, but no deliveries
are created, and anything already held or pending is cancelled. Re-enabling does not back-deliver what arrived
in the meantime — replay exists for that.

Replay and manual retry are refused while a connection is not active.

## Retry policy

A failed delivery is retried after 10s, 1m, 5m, 30m and 2h — six attempts in all, and if the last one fails
the delivery is marked dead.

Each connection can replace that schedule with its own at *Connections → Edit*: a strategy, an interval in
seconds, and a max attempt count. *Linear* waits the interval before every retry; *exponential* starts at the
interval and doubles the wait each retry. Two hard caps apply, whichever is hit first, and both are checked
when you save: at most 50 attempts, and the whole schedule must fit within 7 days.

The policy governs every kind of failure — HTTP errors and transformation errors alike — and applies to manual
retries and replays exactly as it does to first deliveries. Exhausting it marks the delivery dead, the same as
running out the default schedule. Clear the three fields to go back to the default.

## Delivery rate limits

Each destination can cap how fast deliveries go out to it — 1 to 100 per second, or 1 to 6000 per minute — set
on the destination's form at *Destinations → Edit*. Leave the field blank and the destination is unlimited.

Deliveries over the cap are not dropped: they queue and go out as slots free up in the next window. Pacing
works in fixed one-second (or one-minute) windows.

A delivery queued by the rate limit is not a failure. It does not count against connection health, fires no
alerts, and consumes no retry attempts.

The cap is shared by everything aimed at that destination — every connection wired to it, plus automatic
retries, manual retries and replays.

## Event deduplication

Each source can drop repeat deliveries of the same event. Set a **dedupe window** on the source's form at
*Sources → Edit* — 1 to 86400 seconds — and a second copy arriving inside that window is marked a duplicate.
Leave the window blank and the source keeps every request. Saving an identity key without a window enables
deduplication with a 60-second window.

What counts as "the same event" is the **identity key**. The key names a header first — case-insensitively —
and if the request carries no such header it is read as a body path in dot syntax, the same syntax routing
rules use: `data.object.id`. With no key at all, identity is the SHA-256 of the raw body, so byte-identical
bodies collide and nothing else does. If the key resolves to nothing — no such header, no such body path, or
an empty value — the event is treated as unique and delivered.

| Field | Meaning |
| --- | --- |
| Dedupe window (seconds) | 1–86400. Blank disables deduplication. Defaults to 60 if a key is set without one. |
| Identity key | Header name, else body dot path. Blank compares the SHA-256 of the raw body. |

Duplicates are stored and shown in the events list behind a *duplicate* badge — you can still inspect the
headers and body — but they create **zero deliveries**: nothing is sent, nothing fails, no alerts fire. The
window is anchored to the original, never extended by the copies, so the same identity arriving after it
elapses is an ordinary new event.

Deduplication never affects replay. A duplicate can be replayed, and an original can be replayed again, exactly
like any other event.

## Payload transformations

Each connection can carry a JavaScript `transform(request)` function that reshapes the request before it is
forwarded. Edit it at *Connections → Edit*, below the rule fields. A connection without one forwards the
event byte-identically.

`request` has four fields:

| Field | Meaning |
| --- | --- |
| `headers` | The headers the event arrived with, as an object. |
| `body` | The received body. JSON bodies arrive **parsed**, so `request.body.type` works; anything else is the raw string. |
| `path` | Path the webhook arrived on. Input only. |
| `query` | Query string it arrived with. Input only. |

Only `headers` and `body` of the returned object affect the outbound request. A body object is serialized to
JSON, a body string is sent as-is. `path` and `query` are there for deriving values — deliveries always go to
the destination's URL, so returning them changes nothing.

```js
function transform(request) {
  return {
    headers: { "Content-Type": "application/json", "X-Source": "hookrail" },
    body: { id: request.body.id, status: request.body.data.object.status }
  };
}
```

The code runs in an embedded V8 isolate with no network, no filesystem, and no `require`/`import`, and is
killed after 1 second. Code that doesn't parse or doesn't define `transform` is rejected when you save it.

A transform that throws, times out, or returns a non-object fails the delivery **before anything is sent** —
the destination never sees a half-transformed request. That failure is an ordinary delivery failure: it feeds
the same retry schedule, backoff, and unhealthy-connection alerting as an HTTP error, and the attempt records
an error starting with `TransformationError:`, shown on the event page behind a *transform error* pill.

Transforms apply identically to first deliveries, automatic retries, manual retries, and replays. Each attempt
stores the headers and body the transform produced, so you can see exactly what was sent.

To try code before saving it, pick a recent event on the connection's edit page and hit *Preview*; nothing is
delivered. The same preview is available over the API as
`POST /api/v1/connections/:id/transformation_preview`.

## Alert webhooks

The three incident alerts Hookrail sends by email — a connection going unhealthy, that connection recovering,
and an inbound webhook being quarantined — can also be POSTed as signed JSON to one URL per organization.
Point chat or incident tooling at it and you stop depending on someone reading an inbox. Configure it at
*Dashboard → Alert webhook*, or over the API at `/api/v1/alert_webhook`.

Every alert has the same envelope: a `type`, the ISO 8601 UTC `occurred_at`, and a per-type `data` object.

```json
{
  "type": "connection.unhealthy",
  "occurred_at": "2026-07-25T15:07:29Z",
  "data": {
    "source": "Stripe",
    "destination": "Billing worker",
    "consecutive_failures": 5,
    "unhealthy_since": "2026-07-25T15:06:58Z"
  }
}
```

| `type` | `data` fields |
| --- | --- |
| `connection.unhealthy` | `source`, `destination`, `consecutive_failures`, `unhealthy_since` |
| `connection.recovered` | `source`, `destination` |
| `webhook.quarantined` | `source`, `reason`, `received_at` |
| `test` | `message` — sent only by the *Send test alert* button |

Requests are signed exactly like outbound event deliveries: `X-Hookrail-Timestamp` carries the Unix time the
request was built, and `X-Hookrail-Signature` is `sha256=` followed by the HMAC-SHA256 of
`"<timestamp>.<body>"`. The key is a per-org secret, shown next to the URL on the settings page. It is
generated the first time you set a URL, survives later edits to that URL so receivers keep verifying, and is
discarded when you remove the webhook — setting a URL again mints a new one.

Delivery is asynchronous and deliberately expendable: three attempts with backoff, and if the receiver is
still not answering with a 2xx, the alert is dropped with a log line. A failing alert webhook never generates
an alert of its own, never counts against connection health, and never blocks or slows event delivery — there
is no recursion here by design. Use *Send test alert* to fire a sample `test` payload through the same path
and confirm the receiver accepts it.

## Metrics

`/metrics` aggregates delivery health for the current project over the last **24 hours**, **7 days**, or
**30 days**. The 24h window buckets by hour, the others by day.

Four headline numbers sit above the charts. A *delivery* is one event on one connection, and its state is the
latest attempt for that pair:

| Number | Meaning |
| --- | --- |
| Events received | Events ingested in the window. |
| Success rate | Delivered ÷ (delivered + failed). Completed deliveries only — pending ones never drag it down. `—` when nothing has completed. |
| Failed | Deliveries whose latest attempt failed, including those that exhausted their retries and went dead. |
| Pending | Deliveries still in flight, queued, or held. |

Below the charts, a per-connection breakdown sorts worst-offender-first — by failures (the default), by volume,
or by success rate — and a per-destination latency table gives p50 and p95, measured per attempt. Attempts
recorded before latency capture existed are excluded rather than counted as zero.

Complete past days are read from daily rollups, so window totals stay correct after old raw events are pruned.
Latency percentiles come from raw attempts only, so they cover at most the retention period.

## Data retention

One retention window covers the whole org: **7**, **30** (the default), or **90** days, set on the *Data
retention* page or through `PATCH /api/v1/retention`. Every night, events, delivery attempts, and quarantined
webhooks older than the window are hard-deleted. Deletion is permanent — there is no export and no undo.

An event with a delivery still in flight is left alone until that delivery reaches a terminal state, so a
retry in progress is never pruned out from under itself. Metrics daily rollups survive pruning, which is why
`/metrics` totals stay correct once the raw events behind them are gone, and configuration — sources,
destinations, connections, API keys, and settings — is never touched.

## Team members

Every org has exactly one **owner**, and ownership moves only by an explicit transfer on the *Members* page —
the outgoing owner drops to admin in the same step. **Admins** run everything else: settings, API keys,
invitations, and every project in the org. **Members** see only the projects granted to them, each as a
**viewer** (read-only) or an **editor** (create, edit, delete, retry, replay). A member with no grant sees no
projects at all.

Invites are links, not emails. An admin creates one on the *Members* page, copies the URL, and sends it
however they like. The invitee opens it, signs in with GitHub, and joins the org — their GitHub account email
must match the address on the invitation, so a forwarded link is useless to anyone else. Links expire after
**7 days** and can be revoked at any time before they are used.

Incident alert emails — unhealthy connection, recovered connection, quarantined webhook — go to every owner
and admin in the org with a known email address.
