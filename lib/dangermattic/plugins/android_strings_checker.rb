# frozen_string_literal: true

module Danger
  # Plugin for checking the strings.xml localization files for Android.
  #
  # @example Check if a strings.xml file refers to another string resource
  #
  #          android_strings_checker.check_strings_do_not_refer_resource
  #
  # @example Check that existing translatable strings are not modified in place
  #
  #          android_strings_checker.check_existing_strings_not_modified
  #
  # @see Automattic/dangermattic
  # @tags android, localization
  #
  class AndroidStringsChecker < Plugin
    MESSAGE = "This PR adds a translatable entry which references another string resource; this usually causes issues with translations.\n" \
              'Please make sure to set the `translatable="false"` attribute.'

    STRING_MODIFIED_MESSAGE = 'This PR changes the value of an existing translatable string. Existing string keys must stay immutable so that ' \
                              'in-progress and existing translations remain valid: please add a **new** string key for the new copy instead of ' \
                              'editing the existing one (old translations stay attached to the old key).'

    # Default file selector: only the app's source (English) strings, living at `…/res/values/strings.xml`.
    # This deliberately excludes localized `values-<locale>/strings.xml` files (whose values legitimately change
    # when translations are pulled in) and any generated/frozen copies that live outside a `res` directory.
    DEFAULT_SOURCE_STRINGS_SELECTOR = ->(path) { path.match?(%r{(^|/)res/values/strings\.xml$}) }

    # Matches a single-line `<string name="…">value</string>` entry, capturing its name and value.
    STRING_LINE_REGEX = %r{<string\b[^>]*\sname="(?<name>[^"]+)"[^>]*>(?<value>.*)</string>}

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

    # Check that the value of an existing translatable string is not modified in place.
    #
    # In a continuous-localization setup, source strings flow to the translation system constantly, so changing
    # the English value of an existing key silently invalidates the translations already done for that key. The
    # safe convention is to leave existing keys untouched and introduce a new key for any new copy. This check
    # enforces that convention by failing when a `<string>` entry present in the base is modified (rather than
    # added under a new key). Adding new keys, removing keys, and renaming keys are all allowed.
    #
    # @param report_type [Symbol] (optional) Type of report (:error, :warning, :message). Default is :error.
    # @param file_selector [Proc] (optional) Selects which files to check. Defaults to the app's source
    #   `…/res/values/strings.xml` files, excluding localized and generated copies.
    #
    # @return [void]
    def check_existing_strings_not_modified(report_type: :error, file_selector: DEFAULT_SOURCE_STRINGS_SELECTOR)
      files = git_utils.added_and_modified_files.select(&file_selector)

      files.each do |file|
        diff = danger.git.diff_for_file(file)
        next if diff.nil?

        removed = translatable_strings_by_name(git_utils.removed_lines(diff_patch: diff.patch))
        added = translatable_strings_by_name(git_utils.added_lines(diff_patch: diff.patch))

        modified_keys = removed.keys & added.keys
        modified_keys.each do |name|
          next if removed[name].value == added[name].value

          final_message = <<~MESSAGE
            #{STRING_MODIFIED_MESSAGE}
            File `#{file}`, string `#{name}`:
            ```diff
            -#{removed[name].line.chomp}
            +#{added[name].line.chomp}
            ```
          MESSAGE

          reporter.report(message: final_message, type: report_type)
        end
      end
    end

    ParsedString = Struct.new(:value, :line)

    private

    # Parses `<string>` entries out of a set of diff content lines, keyed by their `name` attribute.
    # `translatable="false"` entries are ignored, as they are never sent for translation.
    #
    # @param lines [String] Newline-separated content lines (with the diff `+`/`-` markers already stripped).
    #
    # @return [Hash{String => ParsedString}] A mapping of string name to its parsed value and originating line.
    def translatable_strings_by_name(lines)
      lines.each_line.with_object({}) do |line, result|
        next if line.include?('translatable="false"')

        match = STRING_LINE_REGEX.match(line)
        result[match[:name]] = ParsedString.new(match[:value], line) unless match.nil?
      end
    end
  end
end
