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
