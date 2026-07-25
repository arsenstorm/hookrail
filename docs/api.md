# Hookrail REST API (v1)

JSON API over the same data the UI shows: sources, destinations, connections, events, delivery attempts, and retries.

Base URL: `https://hookrail.dev`
All paths are prefixed with `/api/v1`.

## Authentication

Every request needs a bearer key:

```
Authorization: Bearer hk_...
```

Keys are created in the UI at `/api_keys`. The raw key is shown once at creation and is not recoverable —
only a SHA-256 digest is stored. Revoking a key takes effect immediately.

A key is scoped to one organization. Ids belonging to another organization read exactly like ids that don't
exist: `404`. Nothing about them is leaked.

## Errors

```json
{"error": {"code": "not_found", "message": "Resource not found"}}
```

| Status | `code` | When |
| --- | --- | --- |
| 400 | `bad_request` | Request body is missing the resource wrapper. |
| 401 | `unauthorized` | Missing, malformed, unknown, or revoked key. |
| 404 | `not_found` | Unknown id, or an id owned by another organization. |
| 422 | `validation_failed` | Write rejected; `message` is the model's error sentence. |
| 422 | `not_retryable` | The delivery's latest attempt is not `failed` or `dead`. |
| 422 | `connection_not_active` | The target connection is paused or disabled. |
| 422 | `transformation_failed` | Preview code threw, timed out, or returned a non-object. |

Write bodies are wrapped in the resource name (`{"source": {...}}`). A JSON body without the wrapper is
wrapped automatically; other bodies without it return `400`.

Timestamps are ISO 8601 UTC with milliseconds. `DELETE` returns `204` with no body.

## Sources

A source is an ingest endpoint. Its `token` forms the public ingest URL `https://hookrail.dev/ingest/:token`.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/v1/sources` | `{"sources": [...]}`, ordered by name |
| GET | `/api/v1/sources/:id` | `{"source": {...}}` |
| POST | `/api/v1/sources` | `201` `{"source": {...}}` |
| PATCH/PUT | `/api/v1/sources/:id` | `200` `{"source": {...}}` |
| DELETE | `/api/v1/sources/:id` | `204` — also deletes its events and attempts |

Writable params (all under `source`): `name` (required), plus the inbound-verification config —
`verification_secret`, `verification_header`, `verification_algorithm`, `verification_encoding`,
`verification_header_format`, `verification_signature_prefix`, `verification_signature_key`,
`verification_timestamp_key`, `verification_timestamp_header`, `verification_payload_template`,
`verification_tolerance_seconds`. See the README for what each field means.

Setting `verification_secret` enables verification; sending it blank disables it. Responses expose only the
boolean `verification_enabled` — **the signing secret is never returned by any endpoint**.

```sh
curl -X POST https://hookrail.dev/api/v1/sources \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"source":{"name":"GitHub","verification_secret":"s3cr3t","verification_header":"X-Hub-Signature-256","verification_signature_prefix":"sha256="}}'
```

```json
{
  "source": {
    "id": 12,
    "name": "GitHub",
    "token": "hWkfYSAKs6u55jrYuYyeQ1Ek",
    "created_at": "2026-07-25T15:07:29.593Z",
    "updated_at": "2026-07-25T15:07:29.593Z",
    "verification_enabled": true
  }
}
```

## Destinations

Where events are forwarded.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/v1/destinations` | `{"destinations": [...]}`, ordered by name |
| GET | `/api/v1/destinations/:id` | `{"destination": {...}}` |
| POST | `/api/v1/destinations` | `201` `{"destination": {...}}` |
| PATCH/PUT | `/api/v1/destinations/:id` | `200` `{"destination": {...}}` |
| DELETE | `/api/v1/destinations/:id` | `204` |

Writable params under `destination`: `name` (required), `url` (required), `headers` — a JSON object of extra
request headers sent with each delivery. It replaces the stored object wholesale; there is no merge. Also
`rate_limit` (integer) with `rate_limit_period` (`"second"` or `"minute"`, defaulting to `"second"` when a
limit is set without one) — a cap on how fast deliveries go out. Bounds are 1–100 per second and 1–6000 per
minute; anything outside them is `422` `validation_failed`. Sending `rate_limit` as `null` clears the limit,
and the period with it.

Deliveries beyond the cap queue for the next window: they are never dropped and never count as failures. The
budget is shared across all of the destination's connections, retries and replays.

The destination's `signing_secret` (used to HMAC outbound payloads) is not returned.

```sh
curl -X POST https://hookrail.dev/api/v1/destinations \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"destination":{"name":"Billing worker","url":"https://billing.internal/hooks","headers":{"X-Env":"prod"}}}'
```

```json
{
  "destination": {
    "id": 84,
    "name": "Billing worker",
    "url": "https://billing.internal/hooks",
    "rate_limit": null,
    "rate_limit_period": null,
    "headers": {"X-Env": "prod"},
    "created_at": "2026-07-25T15:07:29.623Z",
    "updated_at": "2026-07-25T15:07:29.623Z"
  }
}
```

## Connections

A connection wires one source to one destination. Events on the source are delivered to every active
connection of that source.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/v1/connections` | `{"connections": [...]}`, newest first |
| GET | `/api/v1/connections/:id` | `{"connection": {...}}` |
| POST | `/api/v1/connections` | `201` `{"connection": {...}}` |
| PATCH/PUT | `/api/v1/connections/:id` | `200` `{"connection": {...}}` |
| DELETE | `/api/v1/connections/:id` | `204` — also deletes its attempts |

Writable params under `connection`: `source_id`, `destination_id`, `status` (default `"active"`), and
`transformation` — a nullable string of JavaScript defining `function transform(request)`, run against every
delivery on this connection (see the README). Code that doesn't parse, or that never defines `transform`, is
rejected with `422 validation_failed`; `null` removes the transform.

`retry_policy` — a nullable object with `strategy` (`"linear"` or `"exponential"`), `interval` (a positive
integer of seconds), and `max_attempts` (1–50). Without one, a failed delivery retries after 10s, 1m, 5m, 30m
and 2h — six attempts, then dead. `"linear"` waits `interval` before every retry; `"exponential"` starts at
`interval` and doubles the wait each retry. The whole schedule must fit within 7 days. Anything else — an
unknown key, a bad strategy, an out-of-range `max_attempts`, a schedule running past 7 days — is
`422 validation_failed`. Send `{}` (or omit all three fields) to clear it back to the default schedule.

`status` is one of `"active"`, `"paused"`, or `"disabled"`; any other value is `422 validation_failed`. A
paused connection still stores matched events but holds their deliveries instead of attempting them, and
releases the held ones in the order the events arrived when you set it back to `"active"`. A disabled
connection creates no deliveries at all and cancels anything already held or pending; re-enabling does not
back-deliver what arrived while it was disabled — use [bulk replay](#bulk-replay) for that. Replay and retry
are refused while a connection is not `"active"`.

A `source_id` or `destination_id` from another organization is rejected with `422 validation_failed`
(`"Source must exist"`), not `404` — the id is resolved through your own project before assignment, so it
reads as absent rather than forbidden. A pair that is already connected is also `422`.

`consecutive_failures` and `unhealthy_since` are read-only health counters. `unhealthy_since` is non-null
once five deliveries in a row fail, and clears on the next success.

```sh
curl -X POST https://hookrail.dev/api/v1/connections \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"connection":{"source_id":12,"destination_id":84}}'
```

```json
{
  "connection": {
    "id": 74,
    "source_id": 12,
    "destination_id": 84,
    "status": "active",
    "transformation": null,
    "retry_policy": null,
    "consecutive_failures": 0,
    "unhealthy_since": null,
    "created_at": "2026-07-25T15:07:29.644Z",
    "updated_at": "2026-07-25T15:07:29.644Z"
  }
}
```

## Transformation preview

`POST /api/v1/connections/:id/transformation_preview`

Runs a transform against one stored event and returns what it produced. Nothing is delivered and nothing is
saved — this is how you check code before writing it to the connection.

| Param | Meaning |
| --- | --- |
| `event_id` | **Required.** An event in your organization; anything else is `404`. |
| `code` | Optional JavaScript to preview, typically unsaved edits. Omitted, the connection's stored `transformation` runs. |

The event is passed to `transform(request)` exactly as a real delivery would pass it: a JSON body arrives
parsed, everything else as the raw string. The response is the transform's `headers` and `body` after
normalization — the body is already serialized, so it is always a string.

Code that throws, times out after 1 second, or returns a non-object is `422 transformation_failed`, with the
JavaScript error in `message`. So is a request with no `code` against a connection that has no stored
transformation.

```sh
curl -X POST https://hookrail.dev/api/v1/connections/74/transformation_preview \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event_id":4021,"code":"function transform(r) { return { headers: { \"X-Env\": \"prod\" }, body: { id: r.body.id } }; }"}'
```

```json
{
  "preview": {
    "headers": {"X-Env": "prod"},
    "body": "{\"id\":42}"
  }
}
```

## Events

Received webhooks, newest first.

### List

`GET /api/v1/events` → `{"events": [...], "next_cursor": "..."}`

Query params, all optional:

| Param | Meaning |
| --- | --- |
| `source_id` | Only events on that source. |
| `status` | Rolled-up delivery status: `delivered`, `failed`, `partial`, `pending`, `undelivered`. Anything else is ignored. |
| `q` | Case-insensitive substring match on the event body. |
| `from` | Inclusive lower bound; parsed as a date and widened to start of day. |
| `to` | Inclusive upper bound; widened to end of day. |
| `cursor` | Opaque page token from a previous `next_cursor`. |

Status buckets are mutually exclusive: `undelivered` has no attempts at all, `pending` has an attempt still in
flight, `delivered` means every attempt succeeded, `failed` means none did, `partial` is a mix. Unparseable
`from`/`to` values are dropped rather than erroring.

Pages hold 50 events. `next_cursor` is `null` on the last page; otherwise pass it back verbatim as `cursor`.
Do not construct or parse cursors yourself.

```sh
curl -G https://hookrail.dev/api/v1/events \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  --data-urlencode "status=failed" \
  --data-urlencode "from=2026-07-01"
```

```json
{
  "events": [
    {
      "id": 4021,
      "source_id": 12,
      "http_method": "POST",
      "path": "/wh",
      "query_string": "a=1",
      "headers": {"Content-Type": "application/json"},
      "body": "{\"hello\":\"world\"}",
      "received_at": "2026-07-25T15:07:29.657Z"
    }
  ],
  "next_cursor": null
}
```

### Show

`GET /api/v1/events/:id` → `{"event": {...}}`, same fields as the list.

```sh
curl https://hookrail.dev/api/v1/events/4021 -H "Authorization: Bearer $HOOKRAIL_KEY"
```

## Attempts

Every delivery try for one event, ordered by connection then attempt number.

`GET /api/v1/events/:event_id/attempts` → `{"attempts": [...]}`

Statuses: `pending`, `delivering`, `succeeded`, `failed`, `dead`. `dead` means retries are exhausted.

`replay` is `true` when the attempt came from a [bulk replay](#bulk-replay) — those requests also carry the
`X-Hookrail-Replay: true` header. Normal deliveries and retries report `false`.

`transformed_headers` and `transformed_body` are the headers and body the connection's transform produced for
this attempt — what was actually sent. Both are `null` when no transform ran, either because the connection
has none or because it failed before sending; a failed transform instead shows up as an `error` starting with
`TransformationError:`.

```sh
curl https://hookrail.dev/api/v1/events/4021/attempts -H "Authorization: Bearer $HOOKRAIL_KEY"
```

```json
{
  "attempts": [
    {
      "id": 395,
      "event_id": 4021,
      "connection_id": 74,
      "attempt_number": 1,
      "status": "failed",
      "response_status": 500,
      "response_body": "boom",
      "error": null,
      "duration_ms": 142,
      "attempted_at": "2026-07-25T15:07:29.667Z",
      "replay": false,
      "transformed_headers": null,
      "transformed_body": null
    }
  ]
}
```

## Retry one delivery

`POST /api/v1/events/:event_id/retries`

| Param | Meaning |
| --- | --- |
| `connection_id` | Required. Must be a connection of that event's source, else `404`. |

Retryable means the latest attempt on that (event, connection) pair ended `failed` or `dead`. Anything else —
succeeded, still in flight, or never attempted — is `422 not_retryable`. A connection that is paused or
disabled is `422 connection_not_active`, checked before retryability. Success is `202`: the delivery is
enqueued, not performed inline.

```sh
curl -X POST https://hookrail.dev/api/v1/events/4021/retries \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"connection_id":74}'
```

```json
{"status": "retrying"}
```

## Bulk retry

`POST /api/v1/events/bulk_retry`

Takes the same filter params as the events list (`source_id`, `status`, `q`, `from`, `to`; `cursor` is
ignored) and retries every retryable delivery in the matching set — not just the first page. With no filters,
that is every retryable delivery in the project.

Returns `202` and the number of deliveries enqueued. Pairs that aren't retryable are skipped, and a pair whose
retry was claimed concurrently is not counted twice, so `enqueued` can be lower than you'd estimate from the
event count.

```sh
curl -X POST https://hookrail.dev/api/v1/events/bulk_retry \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"source_id":12,"status":"failed"}'
```

```json
{"enqueued": 2}
```

## Bulk replay

`POST /api/v1/events/bulk_replay`

Re-sends a filtered set of events to **one** connection you name — backfilling a destination that was down or
newly added. Unlike bulk retry, replay does not care whether a delivery previously failed: an event that
already delivered successfully is sent again.

| Param | Meaning |
| --- | --- |
| `connection_id` | **Required.** A connection in your organization; anything else is `404`. Must be active — paused or disabled is `422 connection_not_active` and nothing is replayed. |
| `source_id`, `status`, `q`, `from`, `to` | Same filters as the events list, selecting the set to replay. `cursor` is ignored. |

Returns `202` and the number of events enqueued. Two kinds of event are skipped and not counted:

- **In flight** — the latest attempt on that (event, connection) pair is `pending` or `delivering`. Replaying would race a delivery already underway.
- **Rule non-matches** — the connection's routing rule doesn't match the event. Replay respects rules exactly as live delivery does.

So `enqueued` can be lower than the number of events your filters match. With no filters, the whole project's
event history is replayed to that connection.

Replayed deliveries carry the header `X-Hookrail-Replay: true` so the destination can distinguish them from
first-time traffic and dedupe. The attempts they create are flagged with `"replay": true` in the attempt JSON
(see [Attempts](#attempts)); normal deliveries and retries report `false`.

```sh
curl -X POST https://hookrail.dev/api/v1/events/bulk_replay \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"connection_id":74,"source_id":12,"from":"2026-07-01"}'
```

```json
{"enqueued": 2}
```

## Alert webhook

An org-scoped singleton: one URL that receives the incident alerts Hookrail otherwise only emails.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/v1/alert_webhook` | `200` `{"alert_webhook": {"url": ..., "secret": ...}}`; both `null` when unconfigured |
| PATCH/PUT | `/api/v1/alert_webhook` | `200` `{"alert_webhook": {...}}` with the URL and its signing secret |
| DELETE | `/api/v1/alert_webhook` | `204`, clearing both the URL and the secret |

Unlike a destination's `signing_secret`, this secret **is** returned. That exception is deliberate: the
operator reading this endpoint is the one configuring the receiver on the other side, and they need the key to
verify what arrives.

Writable param under `alert_webhook`: `url`, which must be an `http(s)` URL — anything else is `422`
`validation_failed`. The secret is generated when a URL is first set and survives later URL edits, so a
receiver you already wired up keeps verifying. Only a `DELETE` discards it; setting a URL afterwards mints a
new one.

```sh
curl -X PUT https://hookrail.dev/api/v1/alert_webhook \
  -H "Authorization: Bearer $HOOKRAIL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"alert_webhook":{"url":"https://hooks.example.com/hookrail"}}'
```

```json
{
  "alert_webhook": {
    "url": "https://hooks.example.com/hookrail",
    "secret": "2f1c9a0b7d4e63a85c19f2b0d7e4a316c8b5f0912a7d43e6"
  }
}
```

### What the receiver gets

A `POST` with a JSON body carrying a `type`, the ISO 8601 UTC `occurred_at`, and a per-type `data` object:

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
| `test` | `message`, from the *Send test alert* button in the UI |

Two headers sign the request, the same pair and construction as outbound event deliveries:

| Header | Value |
| --- | --- |
| `X-Hookrail-Timestamp` | Unix seconds when the request was built. |
| `X-Hookrail-Signature` | `sha256=` + HMAC-SHA256 of `"<timestamp>.<body>"`, keyed by the secret above. |

Delivery is asynchronous with three bounded attempts; after that the alert is dropped with a log line. Alert
delivery never generates alerts of its own and never affects event deliveries.
