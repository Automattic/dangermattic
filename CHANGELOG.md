# Dangermattic CHANGELOG

---

## Trunk

### Breaking Changes

_None_

### New Features

- Add `translation_context_checker` plugin to suggest translator context for changed localization keys using `i18n-context-generator`, with inline and summary reporting options

### Bug Fixes

- Use the extractor's exact Git range and changed locations so punctuation-bearing keys, duplicate keys,
  Android collection members, and changed-only source comments are handled correctly.
- Report partial extraction failures instead of silently dropping them.
- Normalize configured source paths such as `.` and `./Sources`.
- Reject blank source and translation paths before normalization to avoid unintentionally scanning the repository.
- Use machine-readable extractor result states instead of matching placeholder descriptions.
- Group changed source locations by localization occurrence so multiline calls produce one inline result.
- Preserve left/right diff-side metadata, using head fallbacks for apply-ready
  suggestions when translator comments are removed.
- Fall back to plain inline feedback for `.xcstrings` and other formats that do
  not support one-click comment suggestions.
- Include translation-file identity in summary rows and publish inline feedback
  in deterministic file/key/line order.

### Internal Changes

- Require Danger 9.6 and use its native ranged Markdown support instead of a custom GitHub posting layer.
- Run at most one extractor workflow per plugin invocation and delegate translation diff parsing to the extractor.
- Read file diffs only when constructing apply-ready inline suggestions.
- Run the extractor quietly and split extraction, location resolution, suggestion
  rendering, and publication into focused components.
- Bound lint and documentation development dependencies to prevent rule drift.

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
