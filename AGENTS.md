## Overview

Dangermattic is a shared collection of Danger plugins used across Automattic's mobile repositories.
It provides reusable Danger rules for PR checks, code review automation, and CI enforcement.

## Bootstrap

Requires Ruby at the version specified in `.ruby-version`.

```bash
bundle install
```

## Commands

- `bundle exec rake` — run all checks (specs + RuboCop + Danger lint)
- `bundle exec rspec` — run tests only
- `bundle exec rubocop` — run linter only

## Project Structure

- `lib/dangermattic/plugins/` — Danger plugin implementations
- `lib/dangermattic/plugins/common/` — shared helpers used across plugins
- `spec/` — RSpec tests; each plugin has a matching `*_spec.rb`
- `spec/fixtures/` — test fixtures

## Conventions

- Tests written with RSpec
- CI via Buildkite, see `.buildkite`
