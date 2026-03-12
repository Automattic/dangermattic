# frozen_string_literal: true

module Danger
  # Plugin for suggesting translation context on new or modified localized strings.
  #
  # Uses the txcontext gem to analyze how strings are used in source code and
  # generate context descriptions via LLM. Results are posted as inline PR
  # comments on the changed translation file lines and/or as a summary table.
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
  #            report_type: :warning
  #          )
  #
  # @example Summary table only (no inline comments)
  #
  #          translation_context_checker.check_context_suggestions(
  #            translations: 'WooCommerce/Resources/en.lproj/Localizable.strings',
  #            source_paths: ['WooCommerce/'],
  #            inline: false,
  #            summary: true
  #          )
  #
  # @see Automattic/dangermattic
  # @tags localization, translation, context
  #
  class TranslationContextChecker < Plugin
    STRINGS_KEY_PATTERN = /^\+\s*"([^"]+)"\s*=/
    XML_STRING_KEY_PATTERN = /^\+.*<string\s+[^>]*?name=["']([^"']+)["']/
    XML_STRING_ARRAY_KEY_PATTERN = /^\+.*<string-array\s+[^>]*?name=["']([^"']+)["']/
    XML_PLURALS_KEY_PATTERN = /^\+.*<plurals\s+[^>]*?name=["']([^"']+)["']/

    # Analyze new or modified translation keys in the PR and suggest context descriptions
    # to help translators understand how each string is used in the app.
    #
    # @param translations [String, Array<String>] Path(s) to translation file(s) (e.g., Localizable.strings, strings.xml).
    # @param source_paths [String, Array<String>] Path(s) to source code directories to search for string usage.
    # @param inline [Boolean] (optional) Post inline comments on changed translation lines. Default is true.
    # @param summary [Boolean] (optional) Post a summary markdown table with all suggestions. Default is true.
    # @param report_type [Symbol] (optional) Type of inline report (:message, :warning, :error). Default is :message.
    #
    # @return [void]
    def check_context_suggestions(translations:, source_paths:, inline: true, summary: true, report_type: :message)
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
          changed_keys: changed_keys
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

      post_inline_comments(valid_results, changed_translation_files, report_type) if inline
      post_summary_table(valid_results) if summary
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
    def run_extraction(translations:, source_paths:, changed_keys:)
      key_filter = changed_keys.map { |k| Regexp.escape(k) }.join(',')

      config = Txcontext::Config.new(
        translations: translations,
        source_paths: source_paths,
        key_filter: key_filter,
        no_cache: true
      )

      extractor = Txcontext::ContextExtractor.new(config)
      extractor.run
      extractor.results
    end

    # Post inline comments on the translation file lines where keys were changed.
    def post_inline_comments(results, translation_files, report_type)
      key_lines = build_key_line_map(translation_files)

      results.each do |result|
        comment = format_inline_message(result)
        locations = key_lines[result.key]

        if locations&.any?
          locations.each do |location|
            case report_type
            when :warning
              warn(comment, file: location[:file], line: location[:line])
            when :error
              failure(comment, file: location[:file], line: location[:line])
            else
              message(comment, file: location[:file], line: location[:line])
            end
          end
        else
          # Fallback to PR-level comment if line not found
          reporter.report(message: comment, type: report_type)
        end
      end
    end

    # Post a summary markdown table with all context suggestions.
    def post_summary_table(results)
      table = "### Translation Context Suggestions\n\n"
      table += "| Key | Text | Suggested Context | UI Element |\n"
      table += "|-----|------|-------------------|------------|\n"

      results.sort_by(&:key).each do |result|
        key = escape_table_cell(result.key)
        text = escape_table_cell(truncate(result.text.to_s, 50))
        desc = escape_table_cell(result.description.to_s)
        ui = result.ui_element || '-'
        table += "| `#{key}` | #{text} | #{desc} | #{ui} |\n"
      end

      markdown(table)
    end

    XML_FILE_STRING_PATTERN = /<string\s+[^>]*?name=["']([^"']+)["']/
    XML_FILE_STRING_ARRAY_PATTERN = /<string-array\s+[^>]*?name=["']([^"']+)["']/
    XML_FILE_PLURALS_PATTERN = /<plurals\s+[^>]*?name=["']([^"']+)["']/

    # Build a map of translation key -> [{ file:, line: }, ...] for inline comment placement.
    # Returns an array of locations per key to handle the same key appearing in multiple files.
    def build_key_line_map(translation_files)
      map = Hash.new { |h, k| h[k] = [] }

      translation_files.each do |path|
        next unless File.exist?(path)

        File.readlines(path).each_with_index do |line, idx|
          location = { file: path, line: idx + 1 }

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

    def format_inline_message(result)
      parts = ["**Translation Context Suggestion**\n#{result.description}"]

      metadata = []
      metadata << "UI: #{result.ui_element}" if result.ui_element
      metadata << "Tone: #{result.tone}" if result.tone
      metadata << "Max length: #{result.max_length}" if result.max_length

      parts << "*#{metadata.join(' · ')}*" unless metadata.empty?

      parts.join("\n")
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
end
