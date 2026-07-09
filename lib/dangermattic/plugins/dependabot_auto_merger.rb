# frozen_string_literal: true

require 'json'
require 'yaml'

module Danger
  # EXPLORATORY. Approves and enables auto-merge on Dependabot pull requests.
  #
  # Unlike the rest of Dangermattic, this plugin acts on the pull request rather than reporting on it.
  # See the pull request that introduced it for the tradeoffs that entails.
  #
  # Patch updates are auto-merged. Minor updates are auto-merged only for dependencies on an allowlist,
  # and a denylisted dependency is never auto-merged, whatever the update type.
  #
  # @example Auto-merge patch updates
  #
  #          dependabot_auto_merger.auto_merge_patch_updates
  #
  # @example Also auto-merge minor updates to a trusted dependency, and never touch a fragile one
  #
  #          dependabot_auto_merger.auto_merge_patch_updates(
  #            minor_update_allowlist: ['release-toolkit'],
  #            denylist: ['some-fragile-dependency']
  #          )
  #
  # @see Automattic/dangermattic
  # @tags dependabot, github, process
  #
  class DependabotAutoMerger < Plugin
    DEPENDABOT_LOGIN = 'dependabot[bot]'
    PATCH_UPDATE = 'version-update:semver-patch'
    MINOR_UPDATE = 'version-update:semver-minor'
    MERGE_METHODS = %w[MERGE SQUASH REBASE].freeze

    # Approves the pull request and enables auto-merge on it, when the update qualifies.
    #
    # @param minor_update_allowlist [Array<String>] Dependencies that may also be auto-merged on minor updates.
    # @param denylist [Array<String>] Dependencies that must never be auto-merged, whatever the update type.
    # @param merge_method [String] One of `MERGE`, `SQUASH` or `REBASE`.
    #
    # @return [String, nil] The reason auto-merge was enabled, or `nil` when the pull request does not qualify.
    #
    def auto_merge_patch_updates(minor_update_allowlist: [], denylist: [], merge_method: 'MERGE')
      raise ArgumentError, "merge_method must be one of #{MERGE_METHODS.join(', ')}" unless MERGE_METHODS.include?(merge_method)
      return nil unless dependabot_pull_request?

      reason = auto_merge_reason(minor_update_allowlist: minor_update_allowlist, denylist: denylist)
      return nil if reason.nil?

      approve_pull_request(reason: reason) unless already_approved?
      enable_auto_merge(merge_method: merge_method)

      reason
    end

    # The dependencies this pull request updates, as reported by Dependabot in its commit message.
    #
    # @return [Array<Hash>] One entry per dependency, with `dependency-name` and `update-type` keys.
    #
    def updated_dependencies
      # Dependabot appends a YAML document to its commit message; it is the same source `dependabot/fetch-metadata` reads.
      _, _, metadata = dependabot_commit_message.partition(/^---$/)
      return [] if metadata.strip.empty?

      YAML.safe_load(metadata).to_h.fetch('updated-dependencies', [])
    rescue Psych::Exception
      []
    end

    # Whether the pull request was opened by Dependabot from a branch on the repository itself.
    #
    # @return [Boolean]
    #
    def dependabot_pull_request?
      github.pr_author == DEPENDABOT_LOGIN && github.pr_json['head']['repo']['full_name'] == repo_name
    end

    private

    # Why the pull request qualifies for auto-merge, or `nil` when it doesn't.
    def auto_merge_reason(minor_update_allowlist:, denylist:)
      dependencies = updated_dependencies
      return nil if dependencies.empty?

      names = dependencies.map { |dependency| dependency['dependency-name'] }
      return nil if names.any? { |name| denylist.include?(name) }

      # Dependabot reports the highest bump across a group, so a patch here means every dependency in the group is a patch.
      update_types = dependencies.map { |dependency| dependency['update-type'] }.uniq
      return 'all updates are patch level.' if update_types == [PATCH_UPDATE]
      return nil unless update_types == [MINOR_UPDATE]
      return nil unless names.all? { |name| minor_update_allowlist.include?(name) }

      'every dependency in this minor update is on the allowlist.'
    end

    def dependabot_commit_message
      github.api.pull_request_commits(repo_name, pr_number).first&.dig(:commit, :message).to_s
    end

    # Re-approving on every Danger run would spam the pull request, and Danger runs on more events than this plugin cares about.
    def already_approved?
      github.api.pull_request_reviews(repo_name, pr_number).any? do |review|
        review[:state] == 'APPROVED' && review[:user][:login] == authenticated_login
      end
    end

    def approve_pull_request(reason:)
      github.api.create_pull_request_review(
        repo_name,
        pr_number,
        event: 'APPROVE',
        body: "🤖 Auto-approved by Dangermattic, because #{reason}"
      )
    end

    # There is no REST endpoint for auto-merge, so this goes through GraphQL.
    def enable_auto_merge(merge_method:)
      mutation = <<~GRAPHQL
        mutation($pullRequestId: ID!, $mergeMethod: PullRequestMergeMethod!) {
          enablePullRequestAutoMerge(input: { pullRequestId: $pullRequestId, mergeMethod: $mergeMethod }) {
            clientMutationId
          }
        }
      GRAPHQL

      graphql(query: mutation, variables: { pullRequestId: pull_request_node_id, mergeMethod: merge_method })
    end

    def graphql(query:, variables:)
      response = github.api.post('/graphql', { query: query, variables: variables }.to_json)
      errors = response[:errors].to_a
      raise "GraphQL request failed: #{errors.map { |error| error[:message] }.join(', ')}" unless errors.empty?

      response
    end

    def authenticated_login
      @authenticated_login ||= github.api.user[:login]
    end

    def pull_request_node_id
      github.pr_json['node_id']
    end

    def repo_name
      github.pr_json['base']['repo']['full_name']
    end

    def pr_number
      github.pr_json['number']
    end
  end
end
