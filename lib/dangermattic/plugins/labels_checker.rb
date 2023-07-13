# frozen_string_literal: true

module Danger
  # Plugin to check for labels in a PR.
  class LabelsChecker < Plugin
    DEFAULT_DO_NOT_MERGE_LABEL = 'Do Not Merge'
    DEFAULT_LABELS_WARNING = 'Please add the required labels for this project.'
    DEFAULT_REQUIRED_LABELS = [/.*\S.*/].freeze

    # Checks if a PR is missing labels or is marked as 'do not merge'.
    def check(do_not_merge_label: DEFAULT_DO_NOT_MERGE_LABEL, required_labels: DEFAULT_REQUIRED_LABELS,
              required_labels_warning: DEFAULT_LABELS_WARNING)
      github_labels = danger.github.pr_labels

      pr_has_all_required_labels = github_labels.all? do |pr_label|
        required_labels.any? do |required_label|
          pr_label =~ required_label
        end
      end

      if github_labels.empty?
        warn('PR is missing at least one label.')
      elsif !pr_has_all_required_labels
        warn(required_labels_warning)
      end

      # A PR shouldn't be merged with the 'DO NOT MERGE' label.
      found_label = github_labels.find { |label| do_not_merge_label.casecmp?(label) }
      failure("This PR is tagged with '#{found_label}' label.") if found_label
    end
  end
end
