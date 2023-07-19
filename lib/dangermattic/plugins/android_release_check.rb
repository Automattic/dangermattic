# frozen_string_literal: true

module Danger
  # Plugin with checks for Android releases.
  class AndroidReleaseCheck < Plugin
    # Checks if changes made to the release notes are also followed by changes in the Play Store strings file.
    def check_release_notes_and_play_store_strings
      common_release_checks.check_release_notes_and_store_strings(
        release_notes_file: 'metadata/release_notes.txt',
        store_strings_file: 'metadata/PlayStoreStrings.po'
      )
    end

    # Check if there are changes to the internal release notes file RELEASE-NOTES.txt and emit a warning message if that's the case.
    def check_internal_release_notes_changed
      common_release_checks.check_internal_release_notes_changed
    end
  end
end
