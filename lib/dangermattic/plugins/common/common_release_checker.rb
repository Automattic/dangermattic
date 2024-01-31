# frozen_string_literal: true

module Danger
  # Plugin to perform generic checks related to releases.
  # It can be used directly or via the specialised plugins `AndroidReleaseChecker` and `IosReleaseChecker`.
  #
  # @example Checking if a specific file has changed on a release branch:
  #          common_release_checker.check_file_changed(
  #            file_comparison: ->(path) { path == 'metadata/full_release_notes.txt' },
  #            message: 'Release notes have been modified on a release branch.',
  #            on_release_branch: true
  #          )
  #
  # @example Checking if release notes and store strings have changed:
  #          common_release_checker.check_release_notes_and_store_strings(
  #            release_notes_file: 'metadata/release_notes.txt',
  #            po_file: 'metadata/PlayStoreStrings.po'
  #          )
  #
  # @example Checking for changes in internal release notes:
  #          common_release_checker.check_internal_release_notes_changed
  #
  # @see Automattic/dangermattic
  # @tags util, process, release
  #
  class CommonReleaseChecker < Plugin
    DEFAULT_INTERNAL_RELEASE_NOTES = 'RELEASE-NOTES.txt'

    MESSAGE_STORE_FILE_NOT_CHANGED = 'The `%s` file should be updated if the editorialized release notes file `%s` is being changed.'
    MESSAGE_INTERNAL_RELEASE_NOTES_CHANGED = <<~WARNING
      This PR contains changes to `%s`.
      Note that these changes won't affect the final version of the release notes as this version is in code freeze.
      Please, get in touch with a release manager if you want to update the final release notes.
    WARNING

    # Check if certain files have been modified, returning a warning or failure message based on the branch type.
    #
    # @param file_comparison [Proc] Function used to compare modified file paths.
    #   It should take a single argument, which is the path to a modified file,
    #   and return true if the file matches the desired condition.
    #   Example: `file_comparison = ->(file_path) { file_path.include?('app/') }`
    #
    # @param message [String] The message to display in the warning or failure output if the condition is met.
    #
    # @param on_release_branch [Boolean] If true, the check will only run on release branches, otherwise on non-release branches.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @example Check if any modified file is under the 'app/' directory and emit a warning on release branches:
    #   check_file_changed(file_comparison: ->(file_path) { file_path.include?('app/') },
    #                      message: 'Some files in the "app/" directory have been modified. Please review the changes.',
    #                      on_release_branch: true)
    #
    # @example Check if a specific file has been modified and emit a failure on non-release branches:
    #   check_file_changed(file_comparison: ->(file_path) { file_path == 'path/to/file/DoNotChange.java' },
    #                      message: 'The "DoNotChange.java" file has been modified. This change is not allowed on non-release branches.',
    #                      on_release_branch: false,
    #                      report_type: :error)
    #
    # @return [void]
    def check_file_changed(file_comparison:, message:, on_release_branch:, report_type: :warning)
      has_modified_file = git_utils.all_changed_files.any?(&file_comparison)

      should_be_changed = (on_release_branch == github_utils.release_branch?)
      return unless should_be_changed && has_modified_file

      reporter.report(message: message, type: report_type)
    end

    # Check if the release notes and store strings files are correctly updated after a modification to the release notes.
    #
    # @param release_notes_file [String] The name of the release notes file that should be checked for modifications.
    #   Example: 'metadata/release_notes.txt'
    #
    # @param po_file [String] The name of the store strings file that should be checked for modifications.
    #   Example: 'metadata/PlayStoreStrings.po'
    #
    # @example Check if the release notes file 'release_notes.txt' is modified, and the 'PlayStoreStrings.po' file is not modified, posting a message:
    #          check_release_notes_and_store_strings(release_notes_file: 'release_notes.txt', po_file: 'PlayStoreStrings.po')
    #
    # @return [void]
    def check_release_notes_and_store_strings(release_notes_file:, po_file:)
      has_modified_release_notes = danger.git.modified_files.any? { |f| f == release_notes_file }
      has_modified_app_store_strings = danger.git.modified_files.any? { |f| f == po_file }

      return unless has_modified_release_notes && !has_modified_app_store_strings

      message(format(MESSAGE_STORE_FILE_NOT_CHANGED, po_file, release_notes_file))
    end

    # Check if there are changes to the internal release notes file in the release branch and emit a warning if that's the case.
    #
    # @param release_notes_file [String] (optional) The path to the internal release notes file.
    #        Defaults to the `DEFAULT_INTERNAL_RELEASE_NOTES` constant if not provided.
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @example Checking for changes in the default internal release notes file:
    #   check_internal_release_notes_changed
    #
    # @example Checking for changes in a custom internal release notes file at a specific path:
    #   check_internal_release_notes_changed(release_notes_file: '/path/to/internal_release_notes.txt')
    #
    # @return [void]
    def check_internal_release_notes_changed(release_notes_file: DEFAULT_INTERNAL_RELEASE_NOTES, report_type: :warning)
      check_file_changed(
        file_comparison: ->(path) { path == release_notes_file },
        message: format(MESSAGE_INTERNAL_RELEASE_NOTES_CHANGED, release_notes_file),
        on_release_branch: true,
        report_type: report_type
      )
    end
  end
end
