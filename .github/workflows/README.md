# Dangermattic GitHub Workflows Documentation

We provide reusable GitHub workflows to be used with Dangermattic.
Each workflow is designed to be called from other workflows using the `workflow_call` event and input parameters.
All jobs are run on `ubuntu-latest`.

## Check Labels on Issues

**File:** `workflows/reusable-check-labels-on-issues.yml`

This workflow is an independent check (not using Danger) to verify if the labels on an issue match specified regex patterns.

### Inputs:
- `label-format-list`: JSON array of regex strings expected for the labels (default: `[".*"]`)
- `label-error-message`: Error message when labels don't match
- `label-success-message`: Deprecated and ignored. Kept only for backward compatibility with existing callers, and scheduled for removal in the next major release.
- `cancel-running-jobs`: Cancel in-progress jobs when new ones are created (default: `true`)

Example:

```yaml
with:
  label-format-list: |
    [
      "^\\[.+\\]",
      "^[[:alnum:]]"
    ]
```

Backslashes in regex patterns must be doubled because the workflow parses the input as JSON.

### Secrets:
- `github-token`: Required GitHub token
  - The token must resolve through `gh api user` to the same login that appears on issue comments, because the workflow only manages comments authored by that login.

### Job: `check-issue-labels`
- Permissions: `issues: write`
- Main step: "🏷️ Check Issue Labels"
  - Checks if issue labels match the specified regex patterns
  - Updates a managed comment authored by the configured token when labels are missing
  - Removes that managed comment when labels become valid

## Retry Buildkite Step on Pull Request Events

**File:** `workflows/reusable-retry-buildkite-step-on-events.yml`

This workflow retries a specific job in a Buildkite pipeline.

### Inputs:
- `org-slug`: Buildkite organization slug
- `pipeline-slug`: Slug of the Buildkite pipeline to be run
- `retry-step-key`: Key of the Buildkite job to be retried
- `build-commit-sha`: Commit to check for running Buildkite Builds
- `cancel-running-github-jobs`: Cancel in-progress GitHub jobs when new ones are created (default: `true`)

### Secrets:
- `buildkite-api-token`: Required Buildkite API token

### Job: `retry-buildkite-job`
- Main step: "🔄 Retry job on the latest Buildkite Build"
  - Retrieves the latest Buildkite build for the specified commit
  - Identifies the job to retry based on the provided step key
  - Retries the job if it's in an appropriate state (passed, failed, canceled, or finished)

## Run Danger on GitHub

**File:** `workflows/reusable-run-danger.yml`

This workflow runs Danger directly on GitHub Actions.

### Inputs:
- `remove-previous-comments`: Remove previous Danger comments and add a new one (default: `false`)
- `cancel-running-jobs`: Cancel in-progress jobs when new ones are created (default: `true`)

### Secrets:
- `github-token`: Required GitHub token

### Job: `dangermattic`
- Steps:
  1. Checkout repository
  2. Set up Ruby
  3. Run Danger PR Check
     - Executes Danger in read-only mode for forks and Dependabot PRs
     - Runs Danger with full functionality for PRs where the configured token has access to the repo

## Auto-Merge Dependabot Pull Requests

**File:** `workflows/reusable-dependabot-auto-merge.yml`

This workflow approves and enables auto-merge on Dependabot pull requests.
By default it only does so for patch updates; everything else is left for a human to review.

Auto-merge is enabled rather than merging directly, so the pull request still has to pass the repository's required checks before it lands.

### Inputs:
- `merge-method`: The merge method to use, one of `merge`, `squash` or `rebase` (default: `merge`)
- `minor-update-allowlist`: JSON array of dependency names that may also be auto-merged on minor updates (default: `[]`)
- `denylist`: JSON array of dependency names that are never auto-merged, whatever the update type (default: `[]`)

Example:

```yaml
with:
  minor-update-allowlist: |
    [
      "release-toolkit"
    ]
  denylist: |
    [
      "some-fragile-dependency"
    ]
```

For grouped updates, a denylisted dependency anywhere in the group blocks the pull request, and a minor update is only auto-merged when every dependency in the group is on the allowlist.
Names are matched exactly, so `okhttp` on the denylist does not block `okhttp-urlconnection`.

### Secrets:
- `github-token`: Optional GitHub token, defaulting to `GITHUB_TOKEN`
  - Dependabot-triggered runs cannot read Actions secrets, so a token passed here must be stored as a [Dependabot secret](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/configuring-access-to-private-registries-for-dependabot).

### Job: `dependabot-auto-merge`
- Permissions: `contents: write`, `pull-requests: write`
  - A reusable workflow cannot hold more permissions than its caller, so the calling workflow must grant these too.
- Runs only for Dependabot pull requests opened from a branch on the repository itself, never from a fork.
- Steps:
  1. Fetch Dependabot metadata
  2. Decide whether to auto-merge, from the update type and the allow/deny lists
  3. Approve the pull request
  4. Enable auto-merge

The calling workflow must use the `pull_request` event and grant the permissions above:

```yaml
name: 🤖 Auto-merge Dependabot Updates

on:
  pull_request:
    types: [opened, reopened]

permissions:
  contents: write
  pull-requests: write

jobs:
  dependabot-auto-merge:
    uses: Automattic/dangermattic/.github/workflows/reusable-dependabot-auto-merge.yml@v1.5.0
```

The repository must have "Allow auto-merge" enabled, and the organisation must allow GitHub Actions to approve pull requests, otherwise the workflow fails when approving or enabling auto-merge.

These reusable workflows can be incorporated into other workflows in your repository to perform specific tasks related to issue labeling, Buildkite job management, Dependabot updates, and pull request checks using Danger.
