# frozen_string_literal: true

module Danger
  # Plugin for miscellaneous checks for iOS / macOS releases.
  class IosReleaseCheck < Plugin
    # Checks if an existing Core Data model has been edited in a release branch.
    def check_core_data_model_changed
      warning = 'Do not edit an existing Core Data model in a release branch unless it hasn\'t been released to testers yet. ' \
                'Instead create a new model version and merge back to develop soon.'

      common_release_checks.check_file_changed(
        file_comparison: ->(path) { File.extname(path) == '.xcdatamodeld' },
        message: warning,
        on_release: true
      )
    end

    # Checks if the Localizable.strings file has been modified on a regular branch, emiting a warning if that's the case.
    def check_modified_localizable_strings
      common_release_checks.check_file_changed(
        file_comparison: ->(path) { path.end_with?('Resources/en.lproj/Localizable.strings') },
        message: 'Localizable.strings should only be updated on release branches because it is generated automatically.',
        on_release: false
      )
    end

    # Checks if changes made to the release notes are also followed by changes in the App Store strings file.
    def check_release_notes_and_app_store_strings
      common_release_checks.check_release_notes_and_store_strings(
        release_notes_file: 'Resources/release_notes.txt',
        store_strings_file: 'Resources/AppStoreStrings.po'
      )
    end
  end
end
