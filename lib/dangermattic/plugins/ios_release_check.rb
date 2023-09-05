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
    LOCALIZABLE_STRINGS_FILE = 'Localizable.strings'
    BASE_STRINGS_FILE = "en.lproj/#{LOCALIZABLE_STRINGS_FILE}".freeze

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

    # Checks if any Localizable.strings file has been modified on a release branch, otherwise reporting a warning.
    #
    # @return [void]
    def check_modified_localizable_strings_on_release
      common_release_checks.check_file_changed(
        file_comparison: ->(path) { File.basename(path) == LOCALIZABLE_STRINGS_FILE },
        message: "The `#{LOCALIZABLE_STRINGS_FILE}` files should only be updated on release branches, when the translations are downloaded.",
        on_release: false
      )
    end

    # Checks if the en.lproj/Localizable.strings file has been modified on a regular branch, otherwise reporting a warning.
    #
    # @return [void]
    def check_modified_en_strings_on_regular_branch
      common_release_checks.check_file_changed(
        file_comparison: ->(path) { path.end_with?(BASE_STRINGS_FILE) },
        message: "The `#{BASE_STRINGS_FILE}` file should only be updated before creating a release branch.",
        on_release: true
      )
    end

    # Checks if a translation file (*.lproj/Localizable.strings) has been modified on a release branch, otherwise reporting a warning.
    #
    # @return [void]
    def check_modified_translations_on_release_branch
      common_release_checks.check_file_changed(
        file_comparison: ->(path) { !path.end_with?(BASE_STRINGS_FILE) && File.basename(path) == LOCALIZABLE_STRINGS_FILE },
        message: "Translation files `*.lproj/#{LOCALIZABLE_STRINGS_FILE}` should only be updated on a release branch.",
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
