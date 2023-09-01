# frozen_string_literal: true

module Danger
  # Plugin for checking labels associated with a pull request.
  #
  # @example Checking for specific labels and generating warnings/errors:
  #   labels_checker.check(
  #     do_not_merge_labels: ['Do Not Merge'],
  #     required_labels: ['Bug', 'Enhancement'],
  #     required_labels_error: 'Please ensure the PR has labels "Bug" or "Enhancement".',
  #     recommended_labels: ['Documentation'],
  #     recommended_labels_warning: 'Consider adding the "Documentation" label for better tracking.'
  #   )
  #
  # @see Automattic/dangermattic
  # @tags github, process
  #
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
    # @param required_labels [Array<RegExp>] The list of Regular Expressions describing all the type of labels that are *required* on PR (e.g. `[/^feature:/, `/^type:/]` or `bug|bugfix-exemption`).
    #   Defaults to an empty array if not provided.
    # @param required_labels_error [String] The error message displayed if the required labels are not present.
    #   Defaults to a generic message that includes the missing label's regexes.
    # @param recommended_labels [Array<RegExp>] The list of Regular Expressions describing all the type of labels that we want a PR to have,
    # with a warning if it doesn't (e.g. `[/^feature:/, `/^type:/]` or `bug|bugfix-exemption`).
    #   Defaults to an empty array if not provided.
    # @param recommended_labels_warning [String] The warning message displayed if the recommended labels are not present.
    #   Defaults to a generic message that includes the missing label's regexes.
    #
    # @return [void]
    def check(do_not_merge_labels: DEFAULT_DO_NOT_MERGE_LABELS, required_labels: [], required_labels_error: nil, recommended_labels: [], recommended_labels_warning: nil)
      github_labels = danger.github.pr_labels

      # A PR shouldn't be merged with the 'DO NOT MERGE' label
      found_labels = github_labels.select do |github_label|
        do_not_merge_labels.any? { |label| github_label.casecmp?(label) }
      end

      failure("This PR is tagged with #{markdown_list_string(found_labels)} label(s).") unless found_labels.empty?

      # fail if a PR is missing any of the required labels
      check_missing_labels(labels: github_labels, expected_labels: required_labels, fail_on_missing: true, custom_message: required_labels_error)

      # warn if a PR is missing any of the recommended labels
      check_missing_labels(labels: github_labels, expected_labels: recommended_labels, fail_on_missing: false, custom_message: recommended_labels_warning)
    end

    private

    def check_missing_labels(labels:, expected_labels:, fail_on_missing:, custom_message: nil)
      missing_expected_labels = expected_labels.reject do |required_label|
        labels.any? { |label| label =~ required_label }
      end

      return if missing_expected_labels.empty?

      missing_labels_list = missing_expected_labels.map(&:source)
      message = custom_message || "PR is missing label(s) matching: #{markdown_list_string(missing_labels_list)}"

      if fail_on_missing
        failure(message)
      else
        warn(message)
      end
    end

    def markdown_list_string(items)
      items.map { |item| "`#{item}`" }.join(', ')
    end
  end
end
