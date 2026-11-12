# Dangermattic CHANGELOG

---

## Trunk

### Breaking Changes

_None_

### New Features

- Added the `reusable-dependabot-auto-merge` workflow, which approves and enables auto-merge on Dependabot pull requests. Patch updates are auto-merged by default, with optional support for a denylist and for minor updates from an allowlist. [#135]

### Bug Fixes

_None_

### Internal Changes

_None_

## 1.4.1

### Bug Fixes

- `github_utils`: `requested_reviewers?` now detects review requests assigned to a GitHub team when Danger runs with a token that cannot see the organization's teams. [#141]

## 1.4.0

### New Features

- `pr_size_checker`: add optional `line_selector` to `check_diff_size` (and `insertions_size` / `deletions_size` / `diff_size`) to exclude specific changed lines (e.g. comments and blank lines) from the diff-size metric. [#133]

## 1.3.0

### New Features

- Added `android_strings_checker.check_existing_strings_not_modified`, which fails when the value of an existing translatable `<string>` is changed in place (rather than added under a new key). This enforces string-key immutability, which keeps in-progress translations valid in a continuous-localization setup. [#126]

## 1.2.4

### Internal Changes

- `pr_size_checker` and `manifest_pr_checker`: optimize performance for large PRs [#103]

## 1.2.3

### Bug Fixes

- `android_unit_test_checker`: add `annotation` classes as an exception when reporting missing Android unit tests [#101]

## 1.2.2

### Bug Fixes

- `android_unit_test_checker`: add `sealed` and `value` classes as an exception when reporting missing Android unit tests [#94]

## 1.2.1

### Bug Fixes

- Fix `android_unit_test_checker` plugin so it doesn't detect private, enum, and data classes. [#92]
- `view_changes_checker`:  update view checker regex to cover GHE user storage URLs [#91]

## 1.2.0

### New Features

- `manifest_pr_checker`: add check for `Package.resolved` using full paths [#86]

### Bug Fixes

- `view_changes_checker`:  update GitHub assets URL regex to be less strict [#89]

## 1.1.2

### Internal Changes

- Bump Ruby dependencies [#76]

## 1.1.1

### Internal Changes

- Update `danger-rubocop` so that we can run it without `bundle exec`.

## 1.1.0

### New Features

- Reusable GitHub Workflow for retrying Buildkite jobs [#64]

## 1.0.2

### Bug Fixes

- Clean up and update dependencies. [#62]

## 1.0.1

### Bug Fixes

- Fix `tracks_checker` plugin so that only additions / removals in a diff are considered in the check, therefore not including the context parts of the diff. [#58]

## 1.0.0

- After some time being developed and tested across a few repositories, this is our first stable release.
