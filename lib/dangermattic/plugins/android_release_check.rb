# frozen_string_literal: true

module Danger
  # Plugin for performing Android release-related checks in a pull request.
  #
  # @example Checking Android release notes and Play Store strings:
  #          android_release_check.check_release_notes_and_play_store_strings
  #
  # @example Checking for changes in internal release notes:
  #          android_release_check.check_internal_release_notes_changed
  #
  # @see Automattic/dangermattic
  # @tags android, process, release
  #
  class AndroidReleaseCheck < Plugin
    # Checks if changes made to the release notes are also followed by changes in the Play Store strings file.
    #
    # @return [void]
    def check_release_notes_and_play_store_strings
      common_release_checks.check_release_notes_and_store_strings(
        release_notes_file: 'metadata/release_notes.txt',
        store_strings_file: 'metadata/PlayStoreStrings.po'
      )
    end

    # Check if there are changes to the internal release notes file RELEASE-NOTES.txt and emit a warning message if that's the case.
    #
    # @return [void]
    def check_internal_release_notes_changed
      common_release_checks.check_internal_release_notes_changed
    end
  end
end
