# frozen_string_literal: true

require 'yaml'

module Danger
  # Plugin for checking that the Podfile.lock doesn't contain direct commit references.
  #
  # @example Checking a Podfile for commit references:
  #          podfile_checks.check_podfile_does_not_have_commit_references(podfile_lock_path: './aLib/Podfile.lock')
  #
  # @example Checking Git diffs for Podfile.lock commit references:
  #          podfile_checks.check_podfile_diff_does_not_have_commit_references
  #
  # @see Automattic/dangermattic
  # @tags android, localization
  #
  class PodfileChecks < Plugin
    PODFILE_LOCK = 'Podfile.lock'
    PODFILE_LOCK_DEPENDENCIES_ENTRY = 'DEPENDENCIES'
    DEFAULT_PODFILE_LOCK_PATH = './Podfile.lock'

    # Check if the Podfile.lock contains any references to commit hashes and raise a failure if it does.
    #
    # @param podfile_lock_path [String] (optional) The path to the Podfile.lock file.
    #        Defaults to the `DEFAULT_PODFILE_LOCK_PATH` constant if not provided.
    #
    # @example Checking the default Podfile.lock:
    #   check_podfile_does_not_have_commit_references
    #
    # @example Checking a custom Podfile.lock at a specific path:
    #   check_podfile_does_not_have_commit_references(podfile_lock_path: '/path/to/Podfile.lock')
    #
    # @return [void]
    def check_podfile_does_not_have_commit_references(podfile_lock_path: DEFAULT_PODFILE_LOCK_PATH)
      podfile_lock_contents = File.read(podfile_lock_path)
      podfile_lock_data = YAML.load(podfile_lock_contents)

      commit_references = []
      podfile_lock_dependencies = podfile_lock_data[PODFILE_LOCK_DEPENDENCIES_ENTRY]
      podfile_lock_dependencies&.each do |dependency|
        commit_references << dependency if podfile_lock_commit_reference?(podfile_line: dependency)
      end

      return if commit_references.empty?

      failure("Podfile reference(s) to a commit hash:\n```#{commit_references.join("\n")}```")
    end

    # Check for Podfile references to commit hashes in the Podfile.lock in a pull request.
    #
    # @return [void]
    def check_podfile_diff_does_not_have_commit_references
      warning_message = 'This PR adds a Podfile reference to a commit hash:'

      git_utils.check_added_diff_lines(
        file_selector: ->(path) { File.basename(path) == PODFILE_LOCK },
        line_matcher: ->(line) { podfile_lock_commit_reference?(podfile_line: line) },
        message: warning_message
      )
    end

    private

    def podfile_lock_commit_reference?(podfile_line:)
      podfile_line.match?(/\(from `\S+`, commit `\S+`\)/)
    end
  end
end
