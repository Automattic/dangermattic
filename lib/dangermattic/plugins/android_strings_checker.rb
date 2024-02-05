# frozen_string_literal: true

module Danger
  # Plugin for checking the strings.xml localization files for Android.
  #
  # @example Check if a strings.xml file refers to another string resource
  #
  #          android_strings_checker.check_strings_do_not_refer_resource
  #
  # @see Automattic/dangermattic
  # @tags android, localization
  #
  class AndroidStringsChecker < Plugin
    MESSAGE = "This PR adds a translatable entry which references another string resource; this usually causes issues with translations.\n" \
              'Please make sure to set the `translatable="false"` attribute.'

    # Check if translatable strings reference another string resource in 'strings.xml' files in a pull request.
    #
    # @param report_type [Boolean] (optional) Type of report (:error, :warning, :message) whenever a line matches the criteria. Default is :warning.
    #
    # @return [void]
    def check_strings_do_not_refer_resource(report_type: :warning)
      git_utils.check_added_diff_lines(
        file_selector: ->(path) { File.basename(path) == 'strings.xml' },
        line_matcher: ->(line) { line.include?('@string/') && !line.include?('translatable="false"') },
        message: MESSAGE,
        report_type: report_type
      )
    end
  end
end
