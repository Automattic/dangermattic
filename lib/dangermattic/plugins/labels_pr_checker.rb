# frozen_string_literal: true

module Danger
  # Plugin to check for labels in a PR.
  class LabelsPRChecker < Plugin
    # Checks if a PR is missing labels or is marked as 'do not merge'.
    def check_labels
      github_labels = danger.github.pr_labels

      warn('PR is missing at least one label.') if github.pr_labels.empty?

      # A PR shouldn't be merged with the 'DO NOT MERGE' label.
      do_not_merge_label = github_labels.find { |label| do_not_merge_label?(label) }
      failure("This PR is tagged with '#{do_not_merge_label}' label.") if do_not_merge_label
    end

    private

    def do_not_merge_label?(label)
      lc_label = label.downcase
      lc_label.include?('do not merge') || lc_label.include?('not ready for merge')
    end
  end
end
