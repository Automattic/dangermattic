#!/usr/bin/env bash

# Fires N copies of the retry workflow's step at once against a real Buildkite job and asserts on the outcome.
# Usage: RETRY_TOKEN=<write_builds token> validation/double-retry.sh <control|fix> <commit-sha> [copies]

set -euo pipefail

MODE=$1
COMMIT_SHA=$2
COPIES=${3:-5}

ORG_SLUG=automattic
PIPELINE_SLUG=dangermattic
STEP_KEY=rubocop
WORKFLOW=.github/workflows/reusable-retry-buildkite-step-on-events.yml

case "$MODE" in
  control) WORKFLOW_REF=893c2f9 ;; # the commit before "Tolerate a concurrent run retrying the job first"
  fix) WORKFLOW_REF=HEAD ;;
  *) echo "Unknown mode '$MODE'" >&2; exit 2 ;;
esac

: "${RETRY_TOKEN:?RETRY_TOKEN must hold a Buildkite token with write_builds}"

REPO_ROOT=$(git rev-parse --show-toplevel)
WORK=$(mktemp -d)
echo "ℹ️ Working in $WORK"

api() {
  local API_PATH=$1
  shift
  curl --silent --show-error -H "Authorization: Bearer $RETRY_TOKEN" "$@" "https://api.buildkite.com/v2/organizations/$ORG_SLUG/pipelines/$PIPELINE_SLUG/$API_PATH"
}

newest_step_job() {
  api "builds?commit=$COMMIT_SHA" | jq -c --arg key "$STEP_KEY" '.[0] | {number, job: last(.jobs[] | select(.step_key == $key))}'
}

echo "⏳ Waiting for the newest '$STEP_KEY' job on $COMMIT_SHA to finish"
for _ in $(seq 120); do
  TARGET=$(newest_step_job)
  STATE=$(echo "$TARGET" | jq -r '.job.state // "absent"')
  [[ "$STATE" =~ ^(passed|failed|canceled|finished)$ ]] && break
  sleep 5
done
[[ "$STATE" =~ ^(passed|failed|canceled|finished)$ ]] || { echo "❌ Job never finished (state '$STATE')"; exit 1; }

BUILD_NUMBER=$(echo "$TARGET" | jq -r '.number')
TARGET_JOB_ID=$(echo "$TARGET" | jq -r '.job.id')
echo "ℹ️ Target: build $BUILD_NUMBER, job $TARGET_JOB_ID, state $STATE"

# Same substitution the spec performs; the token stays in the environment, never in the file.
# shellcheck disable=SC2016
git -C "$REPO_ROOT" show "$WORKFLOW_REF:$WORKFLOW" | ruby -ryaml -e '
  run = YAML.safe_load($stdin.read)["jobs"]["retry-buildkite-job"]["steps"][0]["run"]
  {
    "inputs.org-slug" => ARGV[0], "inputs.pipeline-slug" => ARGV[1],
    "inputs.retry-step-key" => ARGV[2], "inputs.build-commit-sha" => ARGV[3],
    "secrets.buildkite-api-token" => "$RETRY_TOKEN"
  }.each { |expr, value| run = run.gsub("${{ #{expr} }}", value) }
  abort "unsubstituted expression left in step" if run.include?("${{")
  puts run
' "$ORG_SLUG" "$PIPELINE_SLUG" "$STEP_KEY" "$COMMIT_SHA" > "$WORK/step.sh"

GATE="$WORK/gate"
mkfifo "$GATE"
for i in $(seq "$COPIES"); do
  (
    cat "$GATE" > /dev/null
    set +e
    READ_ONLY_MODE=false bash -e "$WORK/step.sh" > "$WORK/out.$i" 2>&1
    echo $? > "$WORK/status.$i"
  ) &
done
exec 3> "$GATE"
exec 3>&-
wait

for i in $(seq "$COPIES"); do
  echo "── copy $i, exit $(cat "$WORK/status.$i")"
  cat "$WORK/out.$i"
done

count() { grep -l -- "$1" "$WORK"/out.* 2> /dev/null | wc -l | tr -d ' '; }
FAILED=0
for i in $(seq "$COPIES"); do [ "$(cat "$WORK/status.$i")" -eq 0 ] || FAILED=$((FAILED + 1)); done
RETRIED=$(count '✅ Job successfully retried')
TOLERATED=$(count 'already retried by another run')
REFUSED=$(count '❌ Buildkite API call failed')
SAME_JOB=$(count "Job ID for step '$STEP_KEY': $TARGET_JOB_ID")

echo "── read the target $SAME_JOB/$COPIES, retried $RETRIED, tolerated $TOLERATED, refused $REFUSED, failed $FAILED"

echo "── Buildkite's own refusal, from one more PUT on the retried job:"
api "builds/$BUILD_NUMBER/jobs/$TARGET_JOB_ID/retry" -X PUT -w '\nHTTP %{http_code}\n'

echo "── job state after the race:"
api "builds/$BUILD_NUMBER" | jq -c --arg key "$STEP_KEY" '[.jobs[] | select(.step_key == $key) | {id, state, retried, retried_in_job_id}]'

fail() { echo "❌ ASSERTION: $1"; exit 1; }
[ "$SAME_JOB" -eq "$COPIES" ] || fail "only $SAME_JOB of $COPIES copies read job $TARGET_JOB_ID, so they did not race; rerun"
[ "$RETRIED" -eq 1 ] || fail "expected exactly 1 retry, got $RETRIED"

case "$MODE" in
  control)
    [ "$FAILED" -ge 1 ] || fail "the pre-fix step should fail on a concurrent retry, but nothing failed"
    [ "$REFUSED" -eq "$FAILED" ] || fail "every failure should be Buildkite's refusal, but $FAILED failed and $REFUSED were refusals"
    ;;
  fix)
    [ "$FAILED" -eq 0 ] || fail "$FAILED copies failed"
    [ "$TOLERATED" -eq $((COPIES - 1)) ] || fail "expected $((COPIES - 1)) tolerated, got $TOLERATED"
    ;;
esac
echo "✅ $MODE: assertions hold"
