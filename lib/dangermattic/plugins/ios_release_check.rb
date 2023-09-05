# frozen_string_literal: true

module Danger
  # Plugin for performing iOS / macOS release-related checks in a pull request.
  #
  # @example Checking for changes in Core Data models on a release branch:
  #          ios_release_check.check_core_data_model_changed
  #
  # @example Checking for modified Localizable.strings on a regular branch:
  #          ios_release_check.check_modified_localizable_strings
  #
  # @example Checking for synchronization between release notes and App Store strings:
  #          ios_release_check.check_release_notes_and_app_store_strings
  #
  # @see Automattic/dangermattic
  # @tags ios, macos, process, release
  #
  class IosReleaseCheck < Plugin
    # Checks if an existing Core Data model has been edited in a release branch.
    #
    # @return [void]
    def check_core_data_model_changed
      warning = 'Do not edit an existing Core Data model in a release branch unless it hasn\'t been released to testers yet. ' \
                'Instead create a new model version and merge back to develop soon.'

      common_release_checks.check_file_changed(
        file_comparison: ->(path) { File.extname(path) == '.xcdatamodeld' },
        message: warning,
        on_release: true
      )
    end

    # Checks if any Localizable.strings file has been modified on a regular branch, emiting a warning if that's the case.
    #
    # @return [void]
    def check_modified_localizable_strings_on_release
      strings_file = 'Localizable.strings'
      common_release_checks.check_file_changed(
        file_comparison: ->(path) { File.basename(path) == strings_file  },
        message: "`#{strings_file}` files should only be updated on release branches, when the translations are downloaded.",
        on_release: false
      )
    end

    # Checks if changes made to the release notes are also followed by changes in the App Store strings file.
    #
    # @return [void]
    def check_release_notes_and_app_store_strings
      common_release_checks.check_release_notes_and_store_strings(
        release_notes_file: 'Resources/release_notes.txt',
        po_file: 'Resources/AppStoreStrings.po'
      )
    end
  end
end
