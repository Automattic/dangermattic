# frozen_string_literal: true

require 'yaml'

module Danger
  # Plugin for checking that the Podfile.lock doesn't contain direct commit references.
  #
  # @example Checking a Podfile for commit references:
  #          podfile_checker.check_podfile_does_not_have_commit_references(podfile_lock_path: './aLib/Podfile.lock')
  #
  # @example Checking Git diffs for Podfile.lock commit references:
  #          podfile_checker.check_podfile_diff_does_not_have_commit_references
  #
  # @see Automattic/dangermattic
  # @tags android, localization
  #
  class PodfileChecker < Plugin
    PODFILE_LOCK = 'Podfile.lock'
    PODFILE_LOCK_DEPENDENCIES_ENTRY = 'DEPENDENCIES'
    DEFAULT_PODFILE_LOCK_PATH = './Podfile.lock'

    # Check if the Podfile.lock contains any references to commit hashes and raise a failure if it does.
    #
    # @param podfile_lock_path [String] (optional) The path to the Podfile.lock file.
    #        Defaults to the `DEFAULT_PODFILE_LOCK_PATH` constant if not provided.
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error (default), :warning, :message.
    #
    # @example Checking the default Podfile.lock:
    #   check_podfile_does_not_have_commit_references
    #
    # @example Checking a custom Podfile.lock at a specific path:
    #   check_podfile_does_not_have_commit_references(podfile_lock_path: '/path/to/Podfile.lock')
    #
    # @return [void]
    def check_podfile_does_not_have_commit_references(podfile_lock_path: DEFAULT_PODFILE_LOCK_PATH, report_type: :error)
      check_podfile_does_not_match(
        regexp: COMMIT_REFERENCE_REGEXP,
        podfile_lock_path: podfile_lock_path,
        match_found_message_generator: ->(matches) { "Podfile reference(s) to a commit hash:\n```#{matches.join("\n")}```" },
        report_type: report_type
      )
    end

    # Check for Podfile references to commit hashes in the Podfile.lock in a pull request.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_podfile_diff_does_not_have_commit_references(report_type: :warning)
      warning_message = 'This PR adds a Podfile reference to a commit hash:'
      check_podfile_diff_entries_do_not_match(regexp: COMMIT_REFERENCE_REGEXP, match_found_message: warning_message, report_type: report_type)
    end

    # Check if the Podfile.lock contains any references to branches and raise a failure if it does.
    #
    # @param podfile_lock_path [String] (optional) The path to the Podfile.lock file.
    #        Defaults to the `DEFAULT_PODFILE_LOCK_PATH` constant if not provided.
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error (default), :warning, :message.
    #
    # @example Checking the default Podfile.lock:
    #   check_podfile_does_not_have_branch_references
    #
    # @example Checking a custom Podfile.lock at a specific path:
    #    check_podfile_does_not_have_branch_references(podfile_lock_path: '/path/to/Podfile.lock')
    #
    # @return [void]
    def check_podfile_does_not_have_branch_references(podfile_lock_path: DEFAULT_PODFILE_LOCK_PATH, report_type: :error)
      check_podfile_does_not_match(
        regexp: BRANCH_REFERENCE_REGEXP,
        podfile_lock_path: podfile_lock_path,
        match_found_message_generator: ->(matches) { "Podfile reference(s) to a branch:\n```#{matches.join("\n")}```" },
        report_type: report_type
      )
    end

    # Check for Podfile references to branches in the Podfile.lock in a pull request.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_podfile_diff_does_not_have_branch_references(report_type: :warning)
      warning_message = 'This PR adds a Podfile reference to a branch:'
      check_podfile_diff_entries_do_not_match(regexp: BRANCH_REFERENCE_REGEXP, match_found_message: warning_message, report_type: report_type)
    end

    private

    COMMIT_REFERENCE_REGEXP = /\(from `\S+`, commit `\S+`\)/
    BRANCH_REFERENCE_REGEXP = /\(from `\S+`, branch `\S+`\)/

    def check_podfile_does_not_match(
      regexp:,
      podfile_lock_path:,
      match_found_message_generator: ->(matches) { "Matches found in:\n#{matches.join("\n")}" },
      report_type: :error
    )
      podfile_lock_contents = File.read(podfile_lock_path)
      podfile_lock_data = YAML.load(podfile_lock_contents)

      commit_references = []
      podfile_lock_dependencies = podfile_lock_data[PODFILE_LOCK_DEPENDENCIES_ENTRY]
      podfile_lock_dependencies&.each do |dependency|
        commit_references << dependency if dependency.match?(regexp)
      end

      return if commit_references.empty?

      message = match_found_message_generator.call(commit_references)
      reporter.report(message: message, type: report_type)
    end

    def check_podfile_diff_entries_do_not_match(regexp:, match_found_message:, report_type:)
      git_utils.check_added_diff_lines(
        # Notice the lockfile name is not configurable because we check the basename from the files in the diff and one cannot change the name of the lockfile CocoaPods generates.
        file_selector: ->(path) { File.basename(path) == PODFILE_LOCK },
        line_matcher: ->(line) { line.match?(regexp) },
        message: match_found_message,
        report_type: report_type
      )
    end
  end
end
