# frozen_string_literal: true

module Danger
  # Provides common GitHub utility methods related to Pull Requests in a Danger context.
  #
  # @example Checking if the branch is a release or hotfix branch:
  #   github_utils.release_branch? #=> true or false
  #
  # @example Checking if there are active reviewers on the PR:
  #   github_utils.active_reviewers? #=> true or false
  #
  # @example Checking if there are requested teams or reviewers on the PR:
  #   github_utils.requested_reviewers? #=> true or false
  #
  # @example Checking if the branch is a main branch (trunk, main, master, or develop):
  #   github_utils.main_branch? #=> true or false
  #
  # @example Checking if the PR is a work-in-progress (WIP) based on labels or title:
  #   github_utils.wip_feature? #=> true or false
  #
  # @see Automattic/dangermattic
  # @tags tool, util
  #
  class GithubUtils < Plugin
    # Checks if there are active reviewers providing feedback and potentially changing the state of the PR
    # (e.g., approved, changes requested).
    #
    # @return [Boolean] True if there are active reviewers, otherwise false.
    def active_reviewers?
      repo_name = github.pr_json['base']['repo']['full_name']
      pr_number = github.pr_json['number']

      !github.api.pull_request_reviews(repo_name, pr_number).empty?
    end

    # Checks if there are requested teams or reviewers who haven't reacted yet.
    #
    # @return [Boolean] True if there are requested teams or reviewers, otherwise false.
    def requested_reviewers?
      has_requested_reviews = !github.pr_json['requested_teams'].to_a.empty? || !github.pr_json['requested_reviewers'].to_a.empty?
      has_requested_reviews || active_reviewers?
    end

    # Checks if the current branch is a main branch (trunk, main, master, or develop).
    #
    # @return [Boolean] True if the branch is a main branch, otherwise false.
    def main_branch?
      %w[trunk main master develop].include?(github.branch_for_base)
    end

    # Checks if the current branch is a release or hotfix branch.
    #
    # @return [Boolean] True if the branch is a release or hotfix branch, otherwise false.
    def release_branch?
      github.branch_for_base.start_with?('release/') || github.branch_for_base.start_with?('hotfix/')
    end

    # Checks if the PR is a work-in-progress (WIP) based on labels or title.
    #
    # @return [Boolean] True if the PR is a work-in-progress, otherwise false.
    def wip_feature?
      has_wip_label = github.pr_labels.any? { |label| label.include?('WIP') }
      has_wip_title = github.pr_title.include?('WIP')

      has_wip_label || has_wip_title
    end
  end
end
