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
request headers sent with each delivery. It replaces the stored object wholesale; there is no merge.

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

Writable params under `connection`: `source_id`, `destination_id`, `active` (default `true`).

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
    "active": true,
    "consecutive_failures": 0,
    "unhealthy_since": null,
    "created_at": "2026-07-25T15:07:29.644Z",
    "updated_at": "2026-07-25T15:07:29.644Z"
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
      "replay": false
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
succeeded, still in flight, or never attempted — is `422 not_retryable`. Success is `202`: the delivery is
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
| `connection_id` | **Required.** A connection in your organization; anything else is `404`. |
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
