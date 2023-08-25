# frozen_string_literal: true

module Danger
  # Plugin for checking tracks-related changes and providing instructions in the PR if that's the case.
  class CheckTracks < Plugin
    DEFAULT_TRACKS_FILES = [
      'AnalyticsTracker.kt',
      'AnalyticsEvent.kt',
      'LoginAnalyticsTracker.kt',
      'WooAnalyticsStat.swift'
    ].freeze

    DEFAULT_TRACKS_USE_MATCHERS = [
      /AnalyticsTracker\.track/
    ].freeze

    TRACKS_PR_INSTRUCTIONS = <<~MESSAGE
      This PR contains changes to Tracks-related logic. Please ensure the following are completed:
      **PR Author**
      - The PR must be assigned the **Tracks** label
      **PR Reviewer**
      - The events must be validated in the Tracks system.
      - Verify the internal Tracks spreadsheet has also been updated.
    MESSAGE

    # Checks the PR diff for changes in Tracks-related files and provides instructions if changes are detected
    #
    # @param tracks_files [Array<String>] List of Tracks-related file names to check (default: DEFAULT_TRACKS_FILES)
    # @param tracks_usage_match [Array<Regexp>] List of regular expressions representing tracks usages to match the diff lines (default: DEFAULT_TRACKS_FILES)
    # @return [void]
    def check_tracks_changes(tracks_files: DEFAULT_TRACKS_FILES, tracks_usage_matchers: DEFAULT_TRACKS_USE_MATCHERS)
      return unless changes_tracks_files?(tracks_files: tracks_files) || diff_has_tracks_changes?(tracks_usage_matchers: tracks_usage_matchers)

      # tracks related changes detected: publishing instructions
      message(TRACKS_PR_INSTRUCTIONS)
    end

    private

    def changes_tracks_files?(tracks_files:)
      git_utils.all_changed_files.any? do |file|
        tracks_files.any? { |tracks_file| File.basename(file) == File.basename(tracks_file) }
      end
    end

    def diff_has_tracks_changes?(tracks_usage_matchers:)
      matched_lines = git_utils.match_diff_lines_in_files(
        files: git_utils.all_changed_files,
        line_matcher: ->(line) { tracks_usage_matchers.any? { |tracks_usage_match| line.match(tracks_usage_match) } },
        change_type: nil
      )

      !matched_lines.empty?
    end
  end
end
