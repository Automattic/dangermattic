# frozen_string_literal: true

module Danger
  # Plugin for suggesting translation context on new or modified localized strings.
  #
  # Uses the txcontext gem to analyze how strings are used in source code and
  # generate context descriptions via LLM. Results are posted inline on the
  # changed translation file lines and/or as a summary table.
  #
  # Requires the `txcontext` gem to be in the project's Gemfile and the
  # `ANTHROPIC_API_KEY` environment variable to be set in CI.
  #
  # @example Suggest context for new iOS strings
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'WooCommerce/Resources/en.lproj/Localizable.strings',
  #            source_paths: ['WooCommerce/', 'Modules/Sources/']
  #          )
  #
  # @example Suggest context for Android strings with warnings
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'app/src/main/res/values/strings.xml',
  #            source_paths: ['app/src/main/java/'],
  #            provider: :anthropic,
  #            model: 'claude-sonnet-4-6',
  #            report_type: :warning
  #          )
  #
  # @example Summary table only
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'WooCommerce/Resources/en.lproj/Localizable.strings',
  #            source_paths: ['WooCommerce/'],
  #            report_location: :summary
  #          )
  #
  # @example Inline comments and summary table
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'app/src/main/res/values/strings.xml',
  #            source_paths: ['app/src/main/java/'],
  #            report_location: :both
  #          )
  #
  # @example Inline GitHub suggestions that can be applied directly
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'app/src/main/res/values/strings.xml',
  #            source_paths: ['app/src/main/java/'],
  #            inline_suggestions: true
  #          )
  #
  # @example Inline source-code suggestions for Swift localization comments
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'WooCommerce/Resources/en.lproj/Localizable.strings',
  #            source_paths: ['WooCommerce/Classes/'],
  #            inline_suggestions: true,
  #            inline_suggestion_target: :source
  #          )
  #
  # @see Automattic/dangermattic
  # @tags localization, translation, context
  #
  # rubocop:disable Metrics/ClassLength
  class TranslationContextChecker < Plugin
    VALID_REPORT_LOCATIONS = %i[inline summary both none].freeze
    VALID_INLINE_SUGGESTION_TARGETS = %i[translation source].freeze
    STRINGS_KEY_PATTERN = /^\+\s*"([^"]+)"\s*=/
    XML_STRING_KEY_PATTERN = /^\+.*<string\s+[^>]*?name=["']([^"']+)["']/
    XML_STRING_ARRAY_KEY_PATTERN = /^\+.*<string-array\s+[^>]*?name=["']([^"']+)["']/
    XML_PLURALS_KEY_PATTERN = /^\+.*<plurals\s+[^>]*?name=["']([^"']+)["']/
    XML_FILE_STRING_PATTERN = /<string\s+[^>]*?name=["']([^"']+)["']/
    XML_FILE_STRING_ARRAY_PATTERN = /<string-array\s+[^>]*?name=["']([^"']+)["']/
    XML_FILE_PLURALS_PATTERN = /<plurals\s+[^>]*?name=["']([^"']+)["']/
    SWIFT_COMMENT_ARGUMENT_PATTERN = /comment:\s*"((?:\\.|[^"\\])*)"/

    # Analyze new or modified translation keys in the PR and suggest context descriptions
    # to help translators understand how each string is used in the app.
    #
    # @param translations [String, Array<String>] Path(s) to translation file(s) (e.g., Localizable.strings, strings.xml).
    # @param source_paths [String, Array<String>] Path(s) to source code directories to search for string usage.
    # @param report_location [Symbol, String] (optional) Where to post suggestions. Values: :inline (default), :summary, :both.
    # @param inline [Boolean, nil] (optional) Deprecated compatibility flag. When provided, overrides report_location together with summary.
    # @param summary [Boolean, nil] (optional) Deprecated compatibility flag. When provided, overrides report_location together with inline.
    # @param report_type [Symbol] (optional) Type of inline report (:message, :warning, :error). Default is :message.
    # @param provider [Symbol, String] (optional) LLM provider to use. Default is :anthropic.
    # @param model [String, nil] (optional) Model name to use. Uses txcontext defaults when omitted.
    # @param inline_suggestions [Boolean] (optional) Include GitHub suggestion blocks in inline comments when possible. Default is false.
    # @param inline_suggestion_target [Symbol, String] (optional) Target for inline suggestions. Values: :translation (default), :source.
    #
    # @return [void]
    def check_context_suggestions(translations:, source_paths:, report_location: :inline, inline: nil, summary: nil,
                                  report_type: :message, provider: :anthropic, model: nil, inline_suggestions: false,
                                  inline_suggestion_target: :translation)
      report_location = normalize_report_location(report_location, inline: inline, summary: summary)
      return if report_location.nil? || report_location == :none

      inline_suggestion_target = normalize_inline_suggestion_target(inline_suggestion_target)
      return if inline_suggestions && inline_suggestion_target.nil?

      unless load_txcontext
        reporter.report(
          message: '`txcontext` gem is required for translation context suggestions. Add it to your Gemfile.',
          type: :warning
        )
        return
      end

      translations = Array(translations)
      source_paths = Array(source_paths)

      # Only process translation files that were changed in this PR
      changed_translation_files = translations.select do |path|
        git_utils.added_and_modified_files.include?(path)
      end

      return if changed_translation_files.empty?

      # Extract keys from added lines in the diff
      changed_keys = extract_changed_keys(changed_translation_files)
      return if changed_keys.empty?

      # Run txcontext to generate context for the changed keys
      begin
        results = run_extraction(
          translations: translations,
          source_paths: source_paths,
          changed_keys: changed_keys,
          provider: provider,
          model: model
        )
      rescue StandardError => e
        reporter.report(
          message: "Translation context extraction failed: #{e.message}",
          type: :warning
        )
        return
      end
      return if results.empty?

      # Filter out failed results
      valid_results = results.reject { |r| skip_result?(r) }
      return if valid_results.empty?

      if inline_reporting?(report_location)
        post_inline_comments(
          valid_results,
          changed_translation_files,
          report_type,
          inline_suggestions: inline_suggestions,
          inline_suggestion_target: inline_suggestion_target
        )
      end
      post_summary_table(valid_results) if summary_reporting?(report_location)
    end

    private

    # Attempt to load the txcontext gem at runtime.
    # Returns true if available, false otherwise.
    def load_txcontext
      require 'txcontext'
      true
    rescue LoadError
      false
    end

    # Extract translation keys from added lines in the PR diff.
    #
    # @param translation_files [Array<String>] Paths to changed translation files.
    # @return [Set<String>] Set of changed translation keys.
    def extract_changed_keys(translation_files)
      keys = Set.new

      translation_files.each do |path|
        diff = danger.git.diff_for_file(path)
        next unless diff

        ext = File.extname(path).downcase

        diff.patch.each_line do |line|
          next unless line.start_with?('+') && !line.start_with?('+++')

          case ext
          when '.strings'
            keys << Regexp.last_match(1) if line =~ STRINGS_KEY_PATTERN
          when '.xml'
            keys << Regexp.last_match(1) if line =~ XML_STRING_KEY_PATTERN
            keys << Regexp.last_match(1) if line =~ XML_STRING_ARRAY_KEY_PATTERN
            keys << Regexp.last_match(1) if line =~ XML_PLURALS_KEY_PATTERN
          end
        end
      end

      keys
    end

    # Run txcontext extraction for the given keys.
    #
    # @param translations [Array<String>] All translation file paths.
    # @param source_paths [Array<String>] Source code directories.
    # @param changed_keys [Set<String>] Keys to generate context for.
    # @return [Array<Txcontext::ContextExtractor::ExtractionResult>] Extraction results.
    # @raise [StandardError] if extraction fails (caller is responsible for handling).
    def run_extraction(translations:, source_paths:, changed_keys:, provider:, model:)
      key_filter = changed_keys.map { |k| Regexp.escape(k) }.join(',')

      config = Txcontext::Config.new(
        translations: translations,
        source_paths: source_paths,
        key_filter: key_filter,
        provider: provider,
        model: model,
        no_cache: true
      )

      extractor = Txcontext::ContextExtractor.new(config)
      extractor.run
      extractor.results
    end

    # Post inline comments on the translation file lines where keys were changed.
    def post_inline_comments(results, translation_files, report_type, inline_suggestions: false,
                             inline_suggestion_target: :translation)
      key_lines = build_key_line_map(translation_files)

      results.each do |result|
        locations = resolve_inline_locations(
          result,
          key_lines,
          inline_suggestions: inline_suggestions,
          inline_suggestion_target: inline_suggestion_target
        )

        if locations&.any?
          locations.each do |location|
            comment = format_inline_message(result, location: location, inline_suggestions: inline_suggestions)
            next if comment.to_s.empty?

            markdown(comment, file: location[:file], line: location[:line])
          end
        else
          # Fallback to PR-level comment if line not found
          reporter.report(message: format_inline_message(result), type: report_type)
        end
      end
    end

    # Post a summary markdown table with all context suggestions.
    def post_summary_table(results)
      table = "### Translation Context Suggestions\n\n"
      table += "| Key | Text | Suggested Context |\n"
      table += "|-----|------|-------------------|\n"

      results.sort_by(&:key).each do |result|
        key = escape_table_cell(result.key)
        text = escape_table_cell(truncate(result.text.to_s, 50))
        desc = escape_table_cell(format_summary_description(result))
        table += "| `#{key}` | #{text} | #{desc} |\n"
      end

      markdown(table)
    end

    # Build a map of translation key -> [{ file:, line: }, ...] for inline comment placement.
    # Returns an array of locations per key to handle the same key appearing in multiple files.
    def build_key_line_map(translation_files)
      map = Hash.new { |h, k| h[k] = [] }

      translation_files.each do |path|
        next unless File.exist?(path)

        File.readlines(path).each_with_index do |line, idx|
          location = { file: path, line: idx + 1, content: line.chomp }

          case File.extname(path).downcase
          when '.strings'
            map[Regexp.last_match(1)] << location if line =~ /^\s*"([^"]+)"\s*=/
          when '.xml'
            map[Regexp.last_match(1)] << location if line =~ XML_FILE_STRING_PATTERN
            map[Regexp.last_match(1)] << location if line =~ XML_FILE_STRING_ARRAY_PATTERN
            map[Regexp.last_match(1)] << location if line =~ XML_FILE_PLURALS_PATTERN
          end
        end
      end

      map
    end

    def format_inline_message(result, location: nil, inline_suggestions: false)
      suggestion = format_inline_suggestion(result, location)
      return suggestion if inline_suggestions && suggestion

      parts = ['**Translation Context Suggestion**', result.description.to_s]
      parts << "*Max length: #{result.max_length}*" if result.max_length

      parts.join("\n")
    end

    def format_summary_description(result)
      return result.description.to_s unless result.max_length

      "#{result.description} (Max length: #{result.max_length})"
    end

    def format_inline_suggestion(result, location)
      return unless location
      return format_source_inline_suggestion(result, location) if location[:suggestion_target] == :source
      return unless translation_suggestion_supported?(location)

      comment_line = translator_comment_for(result, location)
      return unless comment_line

      [
        '```suggestion',
        comment_line,
        location[:content],
        '```'
      ].join("\n")
    end

    def format_source_inline_suggestion(result, location)
      return unless source_suggestion_supported?(location)

      updated_line = update_swift_comment_argument(location[:content], suggestion_comment_text(result))
      return if updated_line.nil? || updated_line == location[:content]

      [
        '```suggestion',
        updated_line,
        '```'
      ].join("\n")
    end

    def translation_suggestion_supported?(location)
      return false if location[:content].to_s.strip.empty?
      return false if existing_translator_comment?(location)

      %w[.strings .xml].include?(File.extname(location[:file]).downcase)
    end

    def source_suggestion_supported?(location)
      File.extname(location[:file]).downcase == '.swift' &&
        location[:content].to_s.match?(SWIFT_COMMENT_ARGUMENT_PATTERN)
    end

    def existing_translator_comment?(location)
      return false unless File.exist?(location[:file])

      previous_line = File.readlines(location[:file])[location[:line] - 2]
      return false unless previous_line

      stripped = previous_line.strip

      case File.extname(location[:file]).downcase
      when '.strings'
        stripped.start_with?('/*') && stripped.end_with?('*/')
      when '.xml'
        stripped.start_with?('<!--') && stripped.end_with?('-->')
      else
        false
      end
    end

    def translator_comment_for(result, location)
      indentation = location[:content][/^\s*/] || ''
      comment_text = suggestion_comment_text(result)

      case File.extname(location[:file]).downcase
      when '.strings'
        "#{indentation}/* #{escape_strings_comment(comment_text)} */"
      when '.xml'
        "#{indentation}<!-- #{escape_xml_comment(comment_text)} -->"
      end
    end

    def suggestion_comment_text(result)
      return result.description.to_s unless result.max_length

      "#{result.description} Max length: #{result.max_length}."
    end

    def update_swift_comment_argument(content, comment_text)
      replacement = "comment: \"#{escape_swift_string(comment_text)}\""

      content.sub(SWIFT_COMMENT_ARGUMENT_PATTERN, replacement)
    end

    def escape_strings_comment(text)
      text.to_s.gsub('*/', '* /')
    end

    def escape_swift_string(text)
      text
        .to_s
        .gsub('\\', '\\\\')
        .gsub('"', '\\"')
        .gsub("\r", '\\r')
        .gsub("\n", '\\n')
        .gsub("\t", '\\t')
    end

    def escape_xml_comment(text)
      text.to_s.gsub('--', '- -')
    end

    def normalize_report_location(report_location, inline:, summary:)
      return normalize_legacy_report_location(inline: inline, summary: summary) unless inline.nil? && summary.nil?

      normalized = report_location.to_sym
      return normalized if VALID_REPORT_LOCATIONS.include?(normalized)

      reporter.report(
        message: "Invalid report_location `#{report_location}`. Expected one of: #{VALID_REPORT_LOCATIONS.join(', ')}.",
        type: :warning
      )
      nil
    rescue NoMethodError
      reporter.report(
        message: "Invalid report_location `#{report_location}`. Expected one of: #{VALID_REPORT_LOCATIONS.join(', ')}.",
        type: :warning
      )
      nil
    end

    def normalize_legacy_report_location(inline:, summary:)
      legacy_inline = inline.nil? || inline
      legacy_summary = summary.nil? || summary

      return :both if legacy_inline && legacy_summary
      return :inline if legacy_inline
      return :summary if legacy_summary

      :none
    end

    def inline_reporting?(report_location)
      %i[inline both].include?(report_location)
    end

    def normalize_inline_suggestion_target(inline_suggestion_target)
      normalized = inline_suggestion_target.to_sym
      return normalized if VALID_INLINE_SUGGESTION_TARGETS.include?(normalized)

      reporter.report(
        message: "Invalid inline_suggestion_target `#{inline_suggestion_target}`. " \
                 "Expected one of: #{VALID_INLINE_SUGGESTION_TARGETS.join(', ')}.",
        type: :warning
      )
      nil
    rescue NoMethodError
      reporter.report(
        message: "Invalid inline_suggestion_target `#{inline_suggestion_target}`. " \
                 "Expected one of: #{VALID_INLINE_SUGGESTION_TARGETS.join(', ')}.",
        type: :warning
      )
      nil
    end

    def resolve_inline_locations(result, key_lines, inline_suggestions:, inline_suggestion_target:)
      if inline_suggestions && inline_suggestion_target == :source
        source_locations = build_source_line_locations(result)
        return source_locations if source_locations.any?
      end

      Array(key_lines[result.key]).map { |location| location.merge(suggestion_target: :translation) }
    end

    def build_source_line_locations(result)
      Array(result.locations).filter_map do |entry|
        parse_source_location(entry)
      end
    end

    def parse_source_location(entry)
      match = entry.to_s.match(/\A(.+):(\d+)\z/)
      return unless match

      file = match[1]
      line = match[2].to_i
      return unless File.exist?(file)

      lines = File.readlines(file).map(&:chomp)
      return if line < 1 || line > lines.length

      comment_line_index = find_swift_comment_line(lines, line - 1)
      return unless comment_line_index

      {
        file: file,
        line: comment_line_index + 1,
        content: lines[comment_line_index],
        suggestion_target: :source
      }
    end

    def find_swift_comment_line(lines, start_index, lookahead: 8)
      end_index = [lines.length - 1, start_index + lookahead].min

      (start_index..end_index).each do |index|
        line = lines[index]
        return index if line.match?(SWIFT_COMMENT_ARGUMENT_PATTERN)
        break if index > start_index && line.match?(/^\s*\)\s*,?\s*$/)
      end

      nil
    end

    def summary_reporting?(report_location)
      %i[summary both].include?(report_location)
    end

    def skip_result?(result)
      !result.error.nil? ||
        result.description&.include?('No usage found') ||
        result.description&.include?('Processing failed')
    end

    def escape_table_cell(text)
      text.to_s.gsub('|', '\\|').gsub("\n", ' ')
    end

    def truncate(text, length)
      return text if text.length <= length

      "#{text[0, length - 3]}..."
    end
  end
  # rubocop:enable Metrics/ClassLength
end
