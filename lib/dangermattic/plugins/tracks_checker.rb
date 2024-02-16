# frozen_string_literal: true

module Danger
  # Plugin for checking tracks-related changes and providing instructions in the PR if that's the case.
  #
  # @example Checking Tracks changes with default settings:
  #          tracks_checker.check_tracks_changes
  #
  # @example Checking Tracks changes with custom Tracks-related files and usage matchers:
  #          tracks_files = ['AnalyticsTracking.swift', 'AnalyticsHelper.swift']
  #          usage_matchers = [/AnalyticsHelper\.sendEvent/]
  #          tracks_checker.check_tracks_changes(tracks_files: tracks_files, tracks_usage_matchers: usage_matchers)
  #
  # @see Automattic/dangermattic
  # @tags github, pull request, tracks, process
  #
  class TracksChecker < Plugin
    TRACKS_PR_INSTRUCTIONS = <<~MESSAGE
      This PR contains changes to Tracks-related logic. Please ensure (**author and reviewer**) the following are completed:

      - The tracks events must be validated in the Tracks system.
      - Verify the internal Tracks spreadsheet has also been updated.
      - Please consider registering any new events.
    MESSAGE

    TRACKS_NO_LABEL_INSTRUCTION_FORMAT = "- The PR must be assigned the **%s** label.\n"
    TRACKS_NO_LABEL_MESSAGE_FORMAT = 'Please ensure the PR has the `%s` label.'

    # Checks the PR diff for changes in Tracks-related files and provides instructions if changes are detected
    #
    # @param tracks_files [Array<String>] List of Tracks-related file names to check
    # @param tracks_usage_matchers [Array<Regexp>] List of regular expressions representing tracks usages to match the diff lines
    # @param tracks_label [String] A label the check should validate the PR against
    # @return [void]
    def check_tracks_changes(tracks_files:, tracks_usage_matchers:, tracks_label:)
      return unless changes_tracks_files?(tracks_files: tracks_files) || diff_has_tracks_changes?(tracks_usage_matchers: tracks_usage_matchers)

      tracks_message = TRACKS_PR_INSTRUCTIONS

      unless tracks_label.nil? || tracks_label.empty?
        tracks_message += format(TRACKS_NO_LABEL_INSTRUCTION_FORMAT, tracks_label)

        labels_checker.check(
          do_not_merge_labels: [],
          required_labels: [/#{Regexp.escape(tracks_label)}/],
          required_labels_error: format(TRACKS_NO_LABEL_MESSAGE_FORMAT, tracks_label)
        )
      end

      # Tracks-related changes detected: publishing instructions
      message(tracks_message)
    end

    private

    def changes_tracks_files?(tracks_files:)
      git_utils.all_changed_files.any? do |file|
        tracks_files.any? { |tracks_file| File.basename(file) == File.basename(tracks_file) }
      end
    end

    def diff_has_tracks_changes?(tracks_usage_matchers:)
      tracks_changes_on_additions = diff_has_tracks_changes_for_change_type?(
        tracks_usage_matchers: tracks_usage_matchers,
        change_type: :added
      )

      tracks_changes_on_removals = diff_has_tracks_changes_for_change_type?(
        tracks_usage_matchers: tracks_usage_matchers,
        change_type: :removed
      )

      tracks_changes_on_additions || tracks_changes_on_removals
    end

    def diff_has_tracks_changes_for_change_type?(tracks_usage_matchers:, change_type:)
      matched_lines = git_utils.matching_lines_in_diff_files(
        files: git_utils.all_changed_files,
        line_matcher: ->(line) { tracks_usage_matchers.any? { |tracks_usage_match| line.match(tracks_usage_match) } },
        change_type: change_type
      )

      !matched_lines.empty?
    end
  end
end
