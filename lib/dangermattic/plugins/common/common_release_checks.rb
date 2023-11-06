# frozen_string_literal: true

module Danger
  # Plugin to perform generic checks related to releases.
  # It can be used directly or via the specialised plugins `AndroidReleaseCheck` and `IosReleaseCheck`.
  #
  # @example Checking if a specific file has changed on a release branch:
  #          common_release_checks.check_file_changed(
  #            file_comparison: ->(path) { path == 'metadata/full_release_notes.txt' },
  #            message: 'Release notes have been modified on a release branch.',
  #            on_release: true
  #          )
  #
  # @example Checking if release notes and store strings have changed:
  #          common_release_checks.check_release_notes_and_store_strings(
  #            release_notes_file: 'metadata/release_notes.txt',
  #            po_file: 'metadata/PlayStoreStrings.po'
  #          )
  #
  # @example Checking for changes in internal release notes:
  #          common_release_checks.check_internal_release_notes_changed
  #
  # @see Automattic/dangermattic
  # @tags util, process, release
  #
  class CommonReleaseChecks < Plugin
    DEFAULT_INTERNAL_RELEASE_NOTES = 'RELEASE-NOTES.txt'

    # Check if certain files have been modified, returning a warning or failure message based on the branch type.
    #
    # @param file_comparison [Proc] Function used to compare modified file paths.
    #   It should take a single argument, which is the path to a modified file,
    #   and return true if the file matches the desired condition.
    #   Example: `file_comparison = ->(file_path) { file_path.include?('app/') }`
    #
    # @param message [String] The message to display in the warning or failure output if the condition is met.
    #
    # @param on_release [Boolean] If true, the check will only run on release branches, otherwise on non-release branches.
    #
    # @param fail_on_error [Boolean] If true, a failure message will be displayed instead of a warning.
    #
    # @example Check if any modified file is under the 'app/' directory and emit a warning on release branches:
    #   check_file_changed(file_comparison: ->(file_path) { file_path.include?('app/') },
    #                      message: 'Some files in the "app/" directory have been modified. Please review the changes.',
    #                      on_release: true)
    #
    # @example Check if a specific file has been modified and emit a failure on non-release branches:
    #   check_file_changed(file_comparison: ->(file_path) { file_path == 'path/to/file/DoNotChange.java' },
    #                      message: 'The "DoNotChange.java" file has been modified. This change is not allowed on non-release branches.',
    #                      on_release: false,
    #                      fail_on_error: true)
    #
    # @return [void]
    def check_file_changed(file_comparison:, message:, on_release:, fail_on_error: false)
      has_modified_file = git_utils.all_changed_files.any?(&file_comparison)

      should_be_changed = on_release ? release_branch? : !release_branch?
      return unless should_be_changed && has_modified_file

      if fail_on_error
        failure(message)
      else
        warn(message)
      end
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

      report_message = "The `#{po_file}` file should be updated if the editorialised release notes file `#{release_notes_file}` is being changed."
      message(report_message)
    end

    # Check if there are changes to the internal release notes file in the release branch and emit a warning if that's the case.
    #
    # @param release_notes_file [String] (optional) The path to the internal release notes file.
    #        Defaults to the `DEFAULT_INTERNAL_RELEASE_NOTES` constant if not provided.
    #
    # @example Checking for changes in the default internal release notes file:
    #   check_internal_release_notes_changed
    #
    # @example Checking for changes in a custom internal release notes file at a specific path:
    #   check_internal_release_notes_changed(release_notes_file: '/path/to/internal_release_notes.txt')
    #
    # @return [void]
    def check_internal_release_notes_changed(release_notes_file: DEFAULT_INTERNAL_RELEASE_NOTES)
      warning = <<~WARNING
        This PR contains changes to `#{release_notes_file}`.
        Note that these changes won't affect the final version of the release notes as this version is in code freeze.
        Please, get in touch with a release manager if you want to update the final release notes.
      WARNING

      check_file_changed(
        file_comparison: ->(path) { path == release_notes_file },
        message: warning,
        on_release: true,
        fail_on_error: false
      )
    end

    private

    def release_branch?
      danger.github.branch_for_base.start_with?('release/') || danger.github.branch_for_base.start_with?('hotfix/')
    end
  end
end
