# frozen_string_literal: true

module Danger
  # Plugin for performing iOS / macOS release-related checks in a pull request.
  #
  # @example Checking for changes in Core Data models on a release branch:
  #          ios_release_checker.check_core_data_model_changed
  #
  # @example Checking for modified Localizable.strings on a regular branch:
  #          ios_release_checker.check_modified_localizable_strings
  #
  # @example Checking for synchronization between release notes and App Store strings:
  #          ios_release_checker.check_release_notes_and_app_store_strings
  #
  # @see Automattic/dangermattic
  # @tags ios, macos, process, release
  #
  class IosReleaseChecker < Plugin
    LOCALIZABLE_STRINGS_FILE = 'Localizable.strings'
    BASE_STRINGS_FILE = "en.lproj/#{LOCALIZABLE_STRINGS_FILE}".freeze

    MESSAGE_STRINGS_FILE_UPDATED = "The `#{LOCALIZABLE_STRINGS_FILE}` files should only be updated on release branches, when the translations are downloaded by our automation.".freeze
    MESSAGE_BASE_STRINGS_FILE_UPDATED = "The `#{BASE_STRINGS_FILE}` file should only be updated before creating a release branch.".freeze
    MESSAGE_TRANSLATION_FILE_UPDATED = "Translation files `*.lproj/#{LOCALIZABLE_STRINGS_FILE}` should only be updated on a release branch.".freeze
    MESSAGE_CORE_DATA_UPDATED = 'Do not edit an existing Core Data model in a release branch unless it hasn\'t been released to testers yet. ' \
                                'Instead create a new model version and merge back to develop soon.'

    # Checks if an existing Core Data model has been edited in a release branch.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_core_data_model_changed(report_type: :warning)
      common_release_checker.check_file_changed(
        file_comparison: ->(path) { File.extname(path) == '.xcdatamodeld' },
        message: MESSAGE_CORE_DATA_UPDATED,
        on_release_branch: true,
        report_type: report_type
      )
    end

    # Checks if any Localizable.strings file has been modified on a release branch, otherwise reporting a warning.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_modified_localizable_strings_on_release(report_type: :warning)
      common_release_checker.check_file_changed(
        file_comparison: ->(path) { File.basename(path) == LOCALIZABLE_STRINGS_FILE },
        message: MESSAGE_STRINGS_FILE_UPDATED,
        on_release_branch: false,
        report_type: report_type
      )
    end

    # Checks if the en.lproj/Localizable.strings file has been modified on a regular branch, otherwise reporting a warning.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_modified_en_strings_on_regular_branch(report_type: :warning)
      common_release_checker.check_file_changed(
        file_comparison: ->(path) { base_strings_file?(path: path) },
        message: MESSAGE_BASE_STRINGS_FILE_UPDATED,
        on_release_branch: true,
        report_type: report_type
      )
    end

    # Checks if a translation file (*.lproj/Localizable.strings) has been modified on a release branch, otherwise reporting a warning.
    #
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_modified_translations_on_release_branch(report_type: :warning)
      common_release_checker.check_file_changed(
        file_comparison: ->(path) { !base_strings_file?(path: path) && File.basename(path) == LOCALIZABLE_STRINGS_FILE },
        message: MESSAGE_TRANSLATION_FILE_UPDATED,
        on_release_branch: false,
        report_type: report_type
      )
    end

    # Checks if changes made to the release notes are also followed by changes in the App Store strings file.
    #
    # @return [void]
    def check_release_notes_and_app_store_strings
      common_release_checker.check_release_notes_and_store_strings(
        release_notes_file: 'Resources/release_notes.txt',
        po_file: 'Resources/AppStoreStrings.po'
      )
    end

    private

    # Checks if a given path corresponds to the base (English) strings file, en.lproj/Localizable.strings.
    #
    # @return [Boolean] true if path is the base strings file
    def base_strings_file?(path:)
      base_strings_path_components = Pathname.new(BASE_STRINGS_FILE).each_filename.to_a
      path_components = Pathname.new(path).each_filename.to_a

      base_strings_path_components == path_components.last(base_strings_path_components.length)
    end
  end
end
