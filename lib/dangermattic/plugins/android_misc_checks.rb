# frozen_string_literal: true

module Danger
  # Plugin for miscellaneous checks for Android.
  class AndroidMiscChecks < Plugin
    # Check if translatable strings reference another string resource in 'strings.xml' files in a pull request.
    def check_strings_do_not_refer_resource
      warning_message = "This PR adds a translatable entry which references another string resource; this usually causes issues with translations.\n" \
                        'Please make sure to set the `translatable="false"` attribute:'

      git_utils.check_added_diff_lines(
        file_selector: ->(path) { File.basename(path) == 'strings.xml' },
        line_matcher: ->(line) { line.include?('@string/') && !line.include?('translatable="false"') },
        message: warning_message
      )
    end
  end
end
