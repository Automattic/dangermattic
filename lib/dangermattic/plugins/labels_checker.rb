# frozen_string_literal: true

module Danger
  # Plugin to check for labels in a PR.
  class LabelsChecker < Plugin
    DEFAULT_DO_NOT_MERGE_LABELS = [
      'Do Not Merge'
    ].freeze

    # Checks if a PR is missing labels or is marked with labels for not merging.
    # If labels are missing, the plugin will emit a warning. If a label indicating that the PR should not be merged is present,
    # an error will be emitted, preventing the final PR merge.
    #
    # @param do_not_merge_labels [String] The possible labels indicating that a merge should not be allowed.
    #   Defaults to DEFAULT_DO_NOT_MERGE_LABELS if not provided.
    # @param required_labels [Array<String>] The list of RegExes that will prevent the merge if any matching label is present in the PR.
    #   Defaults to an empty array if not provided.
    # @param required_labels_warning [String] The warning message displayed if the required labels are not present.
    #   Defaults to showing the provided label regexes.
    #
    # @return [void]
    def check(do_not_merge_labels: DEFAULT_DO_NOT_MERGE_LABELS, required_labels: [], required_labels_warning: nil)
      github_labels = danger.github.pr_labels

      # A PR shouldn't be merged with the 'DO NOT MERGE' label
      found_labels = github_labels.select do |github_label|
        do_not_merge_labels.any? { |label| github_label.casecmp?(label) }
      end

      failure("This PR is tagged with #{csv_markdown_list(found_labels)} label(s).") unless found_labels.empty?

      # warn if a PR is missing any of the required labels
      missing_required_labels = required_labels.reject do |required_label|
        github_labels.any? { |pr_label| pr_label =~ required_label }
      end

      return if missing_required_labels.empty?

      missing_labels_str_list = missing_required_labels.map(&:source)
      warn(required_labels_warning || "PR is missing label(s) matching: #{csv_markdown_list(missing_labels_str_list)}")
    end

    private

    def csv_markdown_list(items)
      items.map { |item| "`#{item}`" }.join(', ')
    end
  end
end
