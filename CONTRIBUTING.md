# Contributing

Thanks for your interest in improving Hookrail.

## Getting started

You'll need Ruby 3.3.5 and a local Postgres.

```sh
bin/setup          # installs deps, prepares db
bin/dev            # runs web + tailwind watcher
```

App boots at http://localhost:3000.

## Before opening a pull request

Run the same checks CI runs:

```sh
bin/rubocop              # lint
bin/brakeman --no-pager  # Rails security static analysis
bin/bundler-audit        # known-vulnerable gems
bin/importmap audit      # known-vulnerable JS deps
bin/rails test           # unit + integration tests
```

## Coding standards

Style is enforced by RuboCop (rails-omakase). Formatting is not a matter of
opinion here — let the tooling handle it.

Commit messages follow the conventional commit format: `type: message`
(e.g. `fix: retry deliveries with jittered backoff`).

## Reporting issues

Use the issue templates for bugs and feature requests. For security issues, see
[`SECURITY.md`](./SECURITY.md).
