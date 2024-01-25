# frozen_string_literal: true

module Danger
  # Plugin for performing Android release-related checks in a pull request.
  #
  # @example Checking Android release notes and Play Store strings:
  #          android_release_checker.check_release_notes_and_play_store_strings
  #
  # @example Checking for changes in internal release notes:
  #          android_release_checker.check_internal_release_notes_changed
  #
  # @see Automattic/dangermattic
  # @tags android, process, release
  #
  class AndroidReleaseChecker < Plugin
    STRINGS_FILE = 'strings.xml'
    MESSAGE_STRINGS_FILE_UPDATED = "`#{STRINGS_FILE}` files should only be updated on release branches, when the translations are downloaded by our automation.".freeze

    # Checks if changes made to the release notes are also followed by changes in the Play Store strings file.
    #
    # @return [void]
    def check_release_notes_and_play_store_strings
      common_release_checker.check_release_notes_and_store_strings(
        release_notes_file: 'metadata/release_notes.txt',
        po_file: 'metadata/PlayStoreStrings.po'
      )
    end

    # Checks if any strings file (values*/strings.xml) has been modified on a release branch, otherwise reporting a warning / error.
    #
    # @return [void]
    def check_modified_strings_on_release(fail_on_error: false)
      common_release_checker.check_file_changed(
        file_comparison: ->(path) { File.basename(path) == STRINGS_FILE },
        message: MESSAGE_STRINGS_FILE_UPDATED,
        on_release_branch: false,
        fail_on_error: fail_on_error
      )
    end

    # Check if there are changes to the internal release notes file RELEASE-NOTES.txt and emit a warning message if that's the case.
    #
    # @return [void]
    def check_internal_release_notes_changed
      common_release_checker.check_internal_release_notes_changed
    end
  end
end
