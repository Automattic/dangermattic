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

      - The PR must be assigned the **Tracks** label.
      - The tracks events must be validated in the Tracks system.
      - Verify the internal Tracks spreadsheet has also been updated.
      - Please consider registering any new events.
    MESSAGE

    TRACKS_NO_LABEL_MESSAGE = 'Please ensure the PR has the `Tracks` label.'

    # Checks the PR diff for changes in Tracks-related files and provides instructions if changes are detected
    #
    # @param tracks_files [Array<String>] List of Tracks-related file names to check
    # @param tracks_usage_matchers [Array<Regexp>] List of regular expressions representing tracks usages to match the diff lines
    # @return [void]
    def check_tracks_changes(tracks_files:, tracks_usage_matchers:)
      return unless changes_tracks_files?(tracks_files: tracks_files) || diff_has_tracks_changes?(tracks_usage_matchers: tracks_usage_matchers)

      labels_checker.check(
        do_not_merge_labels: [],
        required_labels: [/Tracks/],
        required_labels_error: TRACKS_NO_LABEL_MESSAGE
      )

      # Tracks-related changes detected: publishing instructions
      message(TRACKS_PR_INSTRUCTIONS)
    end

    private

    def changes_tracks_files?(tracks_files:)
      git_utils.all_changed_files.any? do |file|
        tracks_files.any? { |tracks_file| File.basename(file) == File.basename(tracks_file) }
      end
    end

    def diff_has_tracks_changes?(tracks_usage_matchers:)
      matched_lines = git_utils.matching_lines_in_diff_files(
        files: git_utils.all_changed_files,
        line_matcher: ->(line) { tracks_usage_matchers.any? { |tracks_usage_match| line.match(tracks_usage_match) } },
        change_type: nil
      )

      !matched_lines.empty?
    end
  end
end
