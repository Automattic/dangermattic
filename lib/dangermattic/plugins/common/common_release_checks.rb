# frozen_string_literal: true

module Danger
  # Plugin performing a generic checks related to releases. Can be used directly or via specialised plugins as `AndroidReleaseCheck` and `IosReleaseCheck`.
  class CommonReleaseChecks < Plugin
    INTERNAL_RELEASE_NOTES = 'RELEASE-NOTES.txt'

    # Check if certain files have been modified, returning a warning or failure message based on the branch type.
    #
    # @param file_comparison A closure used to compare modified file paths.
    #   The closure should take a single argument, which is the path to a modified file,
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
    #                      on_release: true
    #   )
    #
    # @example Check if a specific file has been modified and emit a failure on non-release branches:
    #   check_file_changed(file_comparison: ->(file_path) { file_path == 'path/to/file/DoNotChange.java' },
    #                      message: 'The "DoNotChange.java" file has been modified. This change is not allowed on non-release branches.',
    #                      on_release: false,
    #                      fail_on_error: true)
    #
    def check_file_changed(file_comparison:, message:, on_release:, fail_on_error: false)
      has_modified_file = all_modified_files.any?(&file_comparison)

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
    # @param store_strings_file [String] The name of the store strings file that should be checked for modifications.
    #   Example: 'metadata/PlayStoreStrings.po'
    #
    # @param fail_on_error [Boolean] If true, a failure message will be emitted instead of a warning.
    #
    # @example Check if the release notes file 'release_notes.txt' is modified, and the 'PlayStoreStrings.po' file is not modified:
    #   check_release_notes_and_store_strings(release_notes_file: 'release_notes.txt', store_strings_file: 'PlayStoreStrings.po', fail_on_error: false)
    #
    def check_release_notes_and_store_strings(release_notes_file:, store_strings_file:, fail_on_error: false)
      has_modified_release_notes = danger.git.modified_files.any? { |f| f.end_with?(release_notes_file) }
      has_modified_app_store_strings = danger.git.modified_files.any? { |f| f.end_with?(store_strings_file) }

      return unless has_modified_release_notes && !has_modified_app_store_strings

      message = "The #{File.basename(store_strings_file)} file must be updated any time changes are made to the release notes."

      if fail_on_error
        failure(message)
      else
        warn(message)
      end
    end

    # Check if there are changes to the internal release notes file in the release branch and emit a warning.
    def check_internal_release_notes_changed
      warning = <<~WARNING
        This PR contains changes to `RELEASE-NOTES.txt`.
        Note that these changes won't affect the final version of the release notes as this version is in code freeze.
        Please, get in touch with a release manager if you want to update the final release notes.
      WARNING

      check_file_changed(
        file_comparison: ->(path) { path.end_with?(INTERNAL_RELEASE_NOTES) },
        message: warning,
        on_release: true,
        fail_on_error: false
      )
    end

    private

    def all_modified_files
      danger.git.added_files + danger.git.modified_files + danger.git.deleted_files
    end

    def release_branch?
      danger.github.branch_for_base.start_with?('release/') || danger.github.branch_for_base.start_with?('hotfix/')
    end
  end
end
