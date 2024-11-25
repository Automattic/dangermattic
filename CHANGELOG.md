# Dangermattic CHANGELOG

---

## Trunk

### Breaking Changes

_None_

### New Features

_None_

### Bug Fixes

_None_

### Internal Changes

_None_

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
