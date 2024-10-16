# Dangermattic GitHub Workflows Documentation

We provide reusable GitHub workflows to be used with Dangermattic.
Each workflow is designed to be called from other workflows using the `workflow_call` event and input parameters.
All jobs are run on `ubuntu-latest`.

## Check Labels on Issues

**File:** `workflows/reusable-check-labels-on-issues.yml`

This workflow is an independent check (not using Danger) to verify if the labels on an issue match specified regex patterns.

### Inputs:
- `label-format-list`: JSON list of regex formats expected for the labels (default: `[".*"]`)
- `label-error-message`: Error message when labels don't match
- `label-success-message`: Success message when labels match
- `cancel-running-jobs`: Cancel in-progress jobs when new ones are created (default: `true`)

### Secrets:
- `github-token`: Required GitHub token

### Job: `check-issue-labels`
- Permissions: `issues: write`
- Main step: "🏷️ Check Issue Labels"
  - Checks if issue labels match the specified regex patterns
  - Posts a comment on the issue with success or error message

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

These reusable workflows can be incorporated into other workflows in your repository to perform specific tasks related to issue labeling, Buildkite job management, and pull request checks using Danger.
