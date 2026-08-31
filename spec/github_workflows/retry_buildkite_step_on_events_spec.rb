# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

# Runs the shell of `reusable-retry-buildkite-step-on-events.yml` against a stubbed Buildkite API.
#
# The workflow's logic lives in an inline `run:` block, which consumers execute without ever checking
# this repository out, so it cannot be extracted to a script. These specs read the block out of the
# YAML, substitute the `${{ … }}` expressions GitHub would resolve, and execute it under `bash -e`
# with a `curl` stub earlier on `PATH` — matching how GitHub Actions runs it.
describe 'reusable-retry-buildkite-step-on-events.yml' do
  let(:org_slug) { 'my-org' }
  let(:pipeline_slug) { 'my-pipeline' }
  let(:step_key) { 'my-step' }
  let(:commit_sha) { '1a2b3c4d' }
  let(:workflow) { YAML.safe_load_file(File.expand_path('../../.github/workflows/reusable-retry-buildkite-step-on-events.yml', __dir__)) }

  describe 'inputs' do
    it 'does not cancel in-progress runs by default' do
      # Callers fire on up to six PR event types; cancelling leaves the earlier run permanently non-green.
      expect(workflow_call_inputs.dig('cancel-running-github-jobs', 'default')).to be(false)
    end
  end

  describe 'the retry step' do
    it 'retries a failed job and reports the new job URL' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'failed')])])

      expect(result[:requests]).to include("PUT #{retry_url(build_number: 42, job_id: 'job-1')}")
      expect(result[:output]).to include('✅ Job successfully retried: https://buildkite.com/retried')
    end

    it 'succeeds without retrying when no build exists for the commit yet' do
      result = run_step(builds: [])

      expect(result[:status]).to be_success
      expect(result[:output]).to include("ℹ️ No Buildkite build for #{commit_sha} — nothing to retry.")
    end

    it 'does not call the retry endpoint when no build exists for the commit yet' do
      result = run_step(builds: [])

      expect(result[:requests]).to eq(["GET #{builds_url}"])
    end

    it 'warns without failing when the build has no job for the step key' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'failed', key: 'another-step')])])

      expect(result[:status]).to be_success
      expect(result[:output]).to include("::warning::Build 42 has no job with step key '#{step_key}' — nothing to retry.")
    end

    it 'retries the newest attempt when the build carries several jobs for the step key' do
      jobs = [job(id: 'job-1', state: 'failed'), job(id: 'job-2', state: 'failed')]
      result = run_step(builds: [build(jobs: jobs)])

      expect(result[:requests]).to eq(["GET #{builds_url}", "PUT #{retry_url(build_number: 42, job_id: 'job-2')}"])
    end

    it 'reads the most recent build when the commit has several' do
      builds = [build(number: 99, jobs: [job(id: 'job-99', state: 'failed')]), build(number: 42, jobs: [job(id: 'job-42', state: 'failed')])]
      result = run_step(builds: builds)

      expect(result[:requests]).to include("PUT #{retry_url(build_number: 99, job_id: 'job-99')}")
    end

    it 'leaves a running job alone' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'running')])])

      expect(result[:status]).to be_success
      expect(result[:requests]).to eq(["GET #{builds_url}"])
    end

    it 'warns without failing when the job is in a state it cannot retry' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'blocked')])])

      expect(result[:status]).to be_success
      expect(result[:output]).to include("::warning::Cannot retry job for step '#{step_key}' in state 'blocked'.")
    end

    it 'fails when the Buildkite API reports an error' do
      result = run_step(builds: { 'message' => 'Not Found' })

      expect(result[:status]).not_to be_success
      expect(result[:output]).to include('❌ Buildkite API call failed: Not Found')
    end

    it 'fails when Buildkite does not confirm the retry' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'failed')])], retry_response: {})

      expect(result[:status]).not_to be_success
      expect(result[:output]).to include("❌ Buildkite did not confirm the retry of step '#{step_key}'.")
    end

    it 'does not call Buildkite at all in read-only mode' do
      result = run_step(builds: [build(jobs: [job(id: 'job-1', state: 'failed')])], read_only: true)

      expect(result[:status]).to be_success
      expect(result[:requests]).to be_empty
    end
  end

  # Psych resolves the workflow's `on:` key as the YAML 1.1 boolean `true`.
  def workflow_call_inputs
    workflow.dig(true, 'workflow_call', 'inputs')
  end

  # Returns the step's shell with the `${{ … }}` expressions GitHub would resolve already substituted.
  def step_script
    script = workflow.dig('jobs', 'retry-buildkite-job', 'steps', 0, 'run')
                     .gsub('${{ inputs.org-slug }}', org_slug)
                     .gsub('${{ inputs.pipeline-slug }}', pipeline_slug)
                     .gsub('${{ inputs.retry-step-key }}', step_key)
                     .gsub('${{ inputs.build-commit-sha }}', commit_sha)
                     .gsub('${{ secrets.buildkite-api-token }}', 'buildkite-token')

    raise "Unsubstituted GitHub expression in the step: #{script[/\$\{\{.*?\}\}/]}" if script.include?('${{')

    script
  end

  def run_step(builds:, retry_response: { 'web_url' => 'https://buildkite.com/retried' }, read_only: false)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'script.sh'), step_script)
      File.write(File.join(dir, 'get.json'), JSON.generate(builds))
      File.write(File.join(dir, 'retry.json'), JSON.generate(retry_response))
      File.write(File.join(dir, 'requests.log'), '')
      write_curl_stub(File.join(dir, 'curl'))

      env = {
        'PATH' => "#{dir}:#{ENV.fetch('PATH')}",
        'READ_ONLY_MODE' => read_only.to_s,
        'STUB_REQUEST_LOG' => File.join(dir, 'requests.log'),
        'STUB_GET_RESPONSE' => File.join(dir, 'get.json'),
        'STUB_RETRY_RESPONSE' => File.join(dir, 'retry.json')
      }
      output, status = Open3.capture2e(env, 'bash', '-e', File.join(dir, 'script.sh'))

      { output: output, status: status, requests: File.read(File.join(dir, 'requests.log')).split("\n") }
    end
  end

  # Writes a `curl` that logs "<method> <url>" and replies with the canned response for that method.
  def write_curl_stub(path)
    File.write(path, <<~BASH)
      #!/usr/bin/env bash
      set -euo pipefail

      METHOD=GET
      URL=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -X) METHOD=$2; shift 2 ;;
          -H) shift 2 ;;
          -*) shift ;;
          *) URL=$1; shift ;;
        esac
      done

      echo "$METHOD $URL" >> "$STUB_REQUEST_LOG"

      if [ "$METHOD" = GET ]; then cat "$STUB_GET_RESPONSE"; else cat "$STUB_RETRY_RESPONSE"; fi
    BASH
    File.chmod(0o755, path)
  end

  def build(number: 42, jobs: [])
    { 'number' => number, 'jobs' => jobs }
  end

  def job(id:, state:, key: step_key)
    { 'id' => id, 'state' => state, 'step_key' => key }
  end

  def api_url(path)
    "https://api.buildkite.com/v2/organizations/#{org_slug}/pipelines/#{pipeline_slug}/#{path}"
  end

  def builds_url
    api_url("builds?commit=#{commit_sha}")
  end

  def retry_url(build_number:, job_id:)
    api_url("builds/#{build_number}/jobs/#{job_id}/retry")
  end
end
