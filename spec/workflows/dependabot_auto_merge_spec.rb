# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'yaml'

# Drives the decision script exactly as it is embedded in the workflow, rather than a copy of it.
# A test against an extracted script would keep passing if the workflow stopped passing it the right environment.
module WorkflowScript
  WORKFLOW = File.expand_path('../../.github/workflows/reusable-dependabot-auto-merge.yml', __dir__)

  # Bash 4 is the floor because the script uses `readarray`. The Buildkite image is Debian, which satisfies it;
  # macOS ships bash 3.2, so developers need a Homebrew bash on their PATH.
  MINIMUM_BASH_VERSION = 4

  module_function

  def workflow
    @workflow ||= YAML.load_file(WORKFLOW)
  end

  def step(id)
    workflow.fetch('jobs').fetch('dependabot-auto-merge').fetch('steps').find { |step| step['id'] == id }
  end

  def decision_script
    step('decision').fetch('run')
  end

  def modern_bash
    @modern_bash ||= ['bash', '/opt/homebrew/bin/bash', '/usr/local/bin/bash'].find do |candidate|
      major, = Open3.capture2e(candidate, '-c', 'echo "${BASH_VERSINFO[0]}"')
      major.to_i >= MINIMUM_BASH_VERSION
    rescue Errno::ENOENT
      false
    end
  end

  def jq?
    @jq ||= system('command -v jq > /dev/null 2>&1')
  end

  # Runs the decision script with the given inputs, returning whether it succeeded and what it decided.
  def decide(update_type:, dependency_names:, denylist: '[]', minor_allowlist: '[]', merge_method: 'merge')
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'decision.sh')
      github_output = File.join(dir, 'github_output')
      File.write(script, decision_script)
      File.write(github_output, '')

      env = {
        'UPDATE_TYPE' => update_type,
        'DEPENDENCY_NAMES' => dependency_names,
        'DENYLIST' => denylist,
        'MINOR_ALLOWLIST' => minor_allowlist,
        'MERGE_METHOD' => merge_method,
        'GITHUB_OUTPUT' => github_output
      }
      output, status = Open3.capture2e(env, modern_bash, script)

      { success: status.success?, merge: File.read(github_output).include?('should-merge=true'), output: output }
    end
  end
end

RSpec.describe 'reusable-dependabot-auto-merge.yml' do # rubocop:disable RSpec/DescribeClass
  # Only the examples that shell out need bash and jq; the ones that merely read the YAML always run.
  before do |example|
    next unless example.metadata[:runs_script]

    missing = []
    missing << 'a bash >= 4' if WorkflowScript.modern_bash.nil?
    missing << 'jq' unless WorkflowScript.jq?
    next if missing.empty?

    message = "Cannot exercise the workflow's decision script without #{missing.join(' and ')}."
    # Skipping on CI would quietly delete this file's coverage, so fail there instead.
    raise message if ENV['CI']

    skip message
  end

  describe 'the decision step' do
    it 'reads every input the script relies on from the environment' do
      # Guards the wiring between the workflow and the script: a renamed input must be renamed in both.
      expect(WorkflowScript.step('decision').fetch('env').keys)
        .to include('UPDATE_TYPE', 'DEPENDENCY_NAMES', 'MINOR_ALLOWLIST', 'DENYLIST', 'MERGE_METHOD')
    end
  end

  describe 'update types', :runs_script do
    it 'auto-merges a patch update' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp')).to include(merge: true)
    end

    it 'does not auto-merge a minor update by default' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-minor', dependency_names: 'okhttp')).to include(merge: false)
    end

    it 'does not auto-merge a major update' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-major', dependency_names: 'okhttp')).to include(merge: false)
    end

    it 'does not auto-merge an unrecognised update type' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-unknown', dependency_names: 'okhttp')).to include(merge: false)
    end
  end

  describe 'grouped updates', :runs_script do
    it 'auto-merges a group where every dependency is a patch' do
      # Dependabot reports the highest bump across a group, so `semver-patch` means the whole group is a patch.
      expect(WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp, retrofit, moshi')).to include(merge: true)
    end

    it 'does not auto-merge when a single dependency in the group is denylisted' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'retrofit,okhttp', denylist: '["okhttp"]')
      expect(result).to include(merge: false)
    end

    it 'does not auto-merge a minor group where only some dependencies are allowlisted' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-minor', dependency_names: 'release-toolkit,okhttp', minor_allowlist: '["release-toolkit"]')
      expect(result).to include(merge: false)
    end
  end

  describe 'the denylist', :runs_script do
    it 'blocks a patch update to a denylisted dependency' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp', denylist: '["okhttp"]')
      expect(result).to include(merge: false)
    end

    it 'takes precedence over the minor update allowlist' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-minor', dependency_names: 'release-toolkit', denylist: '["release-toolkit"]', minor_allowlist: '["release-toolkit"]')
      expect(result).to include(merge: false)
    end

    it 'matches dependency names exactly rather than by prefix' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp-urlconnection', denylist: '["okhttp"]')
      expect(result).to include(merge: true)
    end
  end

  describe 'the minor update allowlist', :runs_script do
    it 'auto-merges a minor update to an allowlisted dependency' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-minor', dependency_names: 'release-toolkit', minor_allowlist: '["release-toolkit"]')
      expect(result).to include(merge: true)
    end

    it 'does not extend to major updates' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-major', dependency_names: 'release-toolkit', minor_allowlist: '["release-toolkit"]')
      expect(result).to include(merge: false)
    end
  end

  describe 'malformed input', :runs_script do
    it 'does not auto-merge when Dependabot reports no dependencies' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: '')).to include(merge: false)
    end

    it 'tolerates surrounding whitespace in the dependency list' do
      expect(WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: "  okhttp \n")).to include(merge: true)
    end

    it 'fails when the denylist is not a JSON array' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp', denylist: '"okhttp"')
      expect(result).to include(success: false, merge: false)
    end

    it 'fails when the denylist holds values that are not strings' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp', denylist: '[1, 2]')
      expect(result).to include(success: false, merge: false)
    end

    it 'fails when the merge method is not one GitHub supports' do
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp', merge_method: 'fast-forward')
      expect(result).to include(success: false, merge: false)
    end

    it 'fails rather than interpolating a merge method that smuggles in a shell command' do
      # `merge-method` reaches `gh pr merge` as an argument, so a caller must not be able to inject through it.
      result = WorkflowScript.decide(update_type: 'version-update:semver-patch', dependency_names: 'okhttp', merge_method: 'merge; touch /tmp/pwned')
      expect(result).to include(success: false, merge: false)
    end
  end
end
