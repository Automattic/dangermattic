# frozen_string_literal: true

require 'pathname'
# Used directly below; keep this entry point independent of transitive requires.
require 'set' # rubocop:disable Lint/RedundantRequireStatement
require 'i18n_context_generator'

module Danger
  # Plugin for suggesting translation context on new or modified localized strings.
  #
  # Uses the i18n-context-generator gem to analyze how strings are used in source code and
  # generate context descriptions via LLM. Results are posted inline on the
  # changed translation file lines and/or as a summary table.
  #
  # Relevant source snippets are sent to the configured external LLM provider.
  # The matching provider API key must be available in CI.
  #
  # @example Suggest context for new iOS strings
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :source,
  #            source_paths: ['WooCommerce/', 'Modules/Sources/'],
  #            inline_mode: :source_suggestion
  #          )
  #
  # @example Suggest context for Android strings with warnings
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :translations,
  #            source_paths: ['app/src/main/java/'],
  #            translation_paths: 'app/src/main/res/values/strings.xml',
  #            provider: :anthropic,
  #            model: 'claude-sonnet-4-6',
  #            report_type: :warning
  #          )
  #
  # @example Summary table only
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :translations,
  #            source_paths: ['WooCommerce/'],
  #            translation_paths: 'WooCommerce/Resources/en.lproj/Localizable.strings',
  #            inline_mode: :none,
  #            summary: true
  #          )
  #
  # @example Inline comments and summary table
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :translations,
  #            source_paths: ['app/src/main/java/'],
  #            translation_paths: 'app/src/main/res/values/strings.xml',
  #            summary: true
  #          )
  #
  # @example Inline GitHub suggestions that can be applied directly
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :translations,
  #            source_paths: ['app/src/main/java/'],
  #            translation_paths: 'app/src/main/res/values/strings.xml',
  #            inline_mode: :translation_suggestion
  #          )
  #
  # @example Inline source-code suggestions for Swift localization comments
  #
  #          translation_context_checker.check_context_suggestions(
  #            discovery_mode: :source,
  #            source_paths: ['WooCommerce/Classes/'],
  #            inline_mode: :source_suggestion
  #          )
  #
  # @see Automattic/dangermattic
  # @tags localization, translation, context
  #
  # rubocop:disable Metrics/ClassLength
  class TranslationContextChecker < Plugin
    VALID_DISCOVERY_MODES = %i[auto translations source].freeze
    VALID_INLINE_MODES = %i[
      translation_comment
      translation_suggestion
      source_comment
      source_suggestion
      none
    ].freeze
    SWIFT_COMMENT_ARGUMENT_PATTERN = /comment:\s*"((?:\\.|[^"\\])*)"/

    # Analyze translation entries or source localization usages changed in the PR
    # and suggest context descriptions to help translators understand how each
    # string is used in the app.
    #
    # @param discovery_mode [Symbol, String] (optional) How to discover entries. Values: :auto, :translations, :source.
    #   Defaults to :auto, which runs one workflow: changed translations take priority, then changed source files.
    #   Invoke the plugin twice with explicit modes when both workflows are wanted for a mixed PR.
    # @param source_paths [String, Array<String>] Path(s) to source code directories or files to search for string usage.
    #   This is required in all modes so code search scope is always explicit.
    # @param translation_paths [String, Array<String>, nil] (optional) Translation file(s) used for translation-backed
    #   discovery and inline placement on translation files (e.g., Localizable.strings, strings.xml).
    #   These are only supported for translation-backed runs.
    # @param inline_mode [Symbol, String, nil] (optional) How to post inline feedback. Values:
    #   :translation_comment, :translation_suggestion, :source_comment, :source_suggestion, :none.
    #   When omitted, the plugin chooses a sensible default based on discovery mode and changed files.
    # @param summary [Boolean] (optional) When true, also post a summary table. Default is false.
    # @param report_type [Symbol] (optional) Severity for PR-level fallback comments (:message, :warning, :error). Default is :message.
    #   Only applies when inline placement fails and the comment falls back to a PR-level report.
    # @param provider [Symbol, String] (optional) LLM provider to use. Default is :anthropic.
    # @param model [String, nil] (optional) Model name to use. Uses i18n-context-generator defaults when omitted.
    #
    # @return [void]
    def check_context_suggestions(source_paths:, discovery_mode: :auto, translation_paths: nil, inline_mode: nil,
                                  summary: false, report_type: :message,
                                  provider: :anthropic, model: nil)
      @file_lines_cache = {}

      discovery_mode = normalize_enum_param(discovery_mode, VALID_DISCOVERY_MODES, 'discovery_mode')
      return if discovery_mode.nil?

      if inline_mode
        inline_mode = normalize_enum_param(inline_mode, VALID_INLINE_MODES, 'inline_mode')
        return if inline_mode.nil?
      end

      if paths_contain_blank?(source_paths)
        reporter.report(message: 'source_paths must not contain blank paths.', type: :warning)
        return
      end
      if paths_contain_blank?(translation_paths)
        reporter.report(message: 'translation_paths must not contain blank paths.', type: :warning)
        return
      end

      translation_paths = normalize_paths(translation_paths)
      configured_source_paths = normalize_paths(source_paths)

      validation_message = validate_context_inputs(
        discovery_mode: discovery_mode,
        source_paths: configured_source_paths,
        translation_paths: translation_paths,
        inline_mode: inline_mode
      )
      if validation_message
        reporter.report(message: validation_message, type: :warning)
        return
      end

      return if inline_mode == :none && !summary

      changed_translation_files = select_changed_translation_files(translation_paths)
      changed_source_files = select_changed_source_files(configured_source_paths, translation_paths: translation_paths)
      resolved_discovery_mode = resolve_discovery_mode(
        discovery_mode,
        changed_translation_files: changed_translation_files,
        changed_source_files: changed_source_files
      )
      return unless resolved_discovery_mode

      inline_mode ||= default_inline_mode_for(
        discovery_mode: resolved_discovery_mode
      )

      begin
        results = run_extraction(
          discovery_mode: resolved_discovery_mode,
          translation_paths: resolved_discovery_mode == :translations ? translation_paths : [],
          source_paths: configured_source_paths,
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

      failed_results, successful_results = results.partition(&:error)
      report_extraction_errors(failed_results)

      actionable_results = successful_results.select(&:actionable?)
      return if actionable_results.empty?

      if inline_reporting?(inline_mode)
        post_inline_comments(
          actionable_results,
          report_type,
          inline_mode: inline_mode
        )
      end
      post_summary_table(actionable_results) if summary
    end

    private

    def select_changed_translation_files(translation_paths)
      changed_files = normalized_changed_files

      translation_paths.select { |path| changed_files.include?(path) }
    end

    def select_changed_source_files(source_paths, translation_paths:)
      changed_files = normalized_changed_files
      translation_files = Set.new(translation_paths)

      changed_files.reject { |path| translation_files.include?(path) }.select do |path|
        source_paths.any? { |source_path| path_matches_source_path?(path, source_path) }
      end
    end

    def path_matches_source_path?(path, source_path)
      normalized_source_path = normalize_path(source_path)
      return true if normalized_source_path == '.'

      path == normalized_source_path || path.start_with?("#{normalized_source_path}/")
    end

    def resolve_discovery_mode(discovery_mode, changed_translation_files:, changed_source_files:)
      case discovery_mode
      when :translations
        :translations unless changed_translation_files.empty?
      when :source
        :source unless changed_source_files.empty?
      else
        return :translations unless changed_translation_files.empty?

        :source unless changed_source_files.empty?
      end
    end

    def normalize_paths(paths)
      Array(paths).compact.map { |path| normalize_path(path) }.uniq
    end

    def paths_contain_blank?(paths)
      Array(paths).compact.any? { |path| path.to_s.strip.empty? }
    end

    def normalize_path(path)
      Pathname.new(path.to_s).cleanpath.to_s
    end

    def normalized_changed_files
      git_utils.added_and_modified_files.map { |path| normalize_path(path) }
    end

    def run_extraction(translation_paths:, source_paths:, provider:, model:, discovery_mode:)
      diff_base, diff_head = danger_diff_range
      config = I18nContextGenerator::Config.new(
        translations: translation_paths,
        source_paths: source_paths,
        discovery_mode: discovery_mode,
        provider: provider,
        model: model,
        no_cache: true,
        diff_base: diff_base,
        diff_head: diff_head
      )

      extractor = I18nContextGenerator::ContextExtractor.new(config)
      extractor.run
      extractor.results
    end

    def danger_diff_range
      [
        Danger::EnvironmentManager.danger_base_branch,
        Danger::EnvironmentManager.danger_head_branch
      ]
    end

    def validate_context_inputs(discovery_mode:, source_paths:, translation_paths:, inline_mode:)
      return 'source_paths is required for translation context suggestions.' if source_paths.empty?
      return 'translation_paths is not supported when discovery_mode is `source`.' if discovery_mode == :source && translation_paths.any?
      return 'translation_paths is required when discovery_mode is `translations`.' if discovery_mode == :translations && translation_paths.empty?
      return 'inline_mode `translation_comment` is not supported when discovery_mode is `source`.' if discovery_mode == :source && inline_mode == :translation_comment
      return 'inline_mode `translation_suggestion` is not supported when discovery_mode is `source`.' if discovery_mode == :source && inline_mode == :translation_suggestion
      return 'inline_mode `translation_comment` requires translation_paths.' if inline_mode == :translation_comment && translation_paths.empty?
      return 'inline_mode `translation_suggestion` requires translation_paths.' if inline_mode == :translation_suggestion && translation_paths.empty?

      nil
    end

    def default_inline_mode_for(discovery_mode:)
      return :source_comment if discovery_mode == :source

      :translation_comment
    end

    # Post inline comments on the translation file lines where keys were changed.
    #
    # Suggestions use Danger's native ranged Markdown support. If no changed
    # inline location is available, a PR-level comment is posted instead.
    def post_inline_comments(results, report_type, inline_mode:)
      inline_suggestions = inline_suggestion_mode?(inline_mode)
      inline_target = inline_target_for(inline_mode)
      added_lines_by_file = if inline_suggestions
                              build_added_line_map(inline_target_files(results, inline_target))
                            else
                              Hash.new { |hash, key| hash[key] = Set.new }
                            end

      results.each do |result|
        locations = resolve_inline_locations(
          result,
          inline_target: inline_target,
          inline_suggestions: inline_suggestions,
          added_lines_by_file: added_lines_by_file
        )

        if locations&.any?
          locations.each do |location|
            location = enrich_inline_location(
              location,
              added_lines_by_file,
              inline_suggestions: inline_suggestions
            )
            comment = format_inline_message(result, location: location, inline_suggestions: inline_suggestions)
            next if comment.to_s.empty?

            post_inline_markdown(comment, location)
          end
        else
          # Fallback to PR-level comment if line not found
          reporter.report(message: format_inline_message(result), type: report_type)
        end
      end
    end

    def post_inline_markdown(comment, location)
      options = { file: location[:file], line: location[:line] }
      options.merge!(start_line: location[:start_line], side: 'RIGHT', start_side: 'RIGHT') if location[:start_line]
      markdown(comment, **options)
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

    def inline_target_files(results, inline_target)
      location_method = inline_target == :source ? :changed_locations : :changed_translation_locations

      results.flat_map { |result| Array(result.public_send(location_method)) }
             .filter_map { |entry| parse_result_location(entry)&.fetch(:file) }
             .uniq
    end

    def build_added_line_map(files)
      map = Hash.new { |h, k| h[k] = Set.new }

      files.each do |path|
        each_added_diff_line(path) do |_line, line_number|
          map[path] << line_number
        end
      end

      map
    end

    # Iterate over added lines in a unified diff, yielding the raw line content
    # (including the leading '+') and the corresponding line number in the new file.
    def each_added_diff_line(path)
      diff = danger.git.diff_for_file(path)
      return unless diff

      new_line_number = nil

      diff.patch.each_line do |line|
        if (match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          new_line_number = match[1].to_i
          next
        end

        next if new_line_number.nil?
        next if line.start_with?('diff --git', 'index ', '--- ', '+++ ', '\\')

        if line.start_with?('+')
          yield(line, new_line_number)
          new_line_number += 1
        elsif line.start_with?('-')
          next
        elsif line.start_with?(' ')
          new_line_number += 1
        end
      end
    end

    def format_inline_message(result, location: nil, inline_suggestions: false)
      if inline_suggestions
        suggestion = format_inline_suggestion(result, location)
        return suggestion if suggestion

        # When a suggestion can't be generated for an unsupported file type,
        # return nil to skip the comment entirely. But when the location has an
        # existing translator comment that can't be expressed as a one-click
        # suggestion (non-added lines), fall through to plain text so the
        # reviewer still sees the recommendation.
        return nil unless location&.dig(:existing_comment)
      end

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
      return format_source_inline_suggestion(result, location) if location[:inline_target] == :source
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
      return false if location[:existing_comment] && !location[:start_line]

      %w[.strings .xml].include?(File.extname(location[:file]).downcase)
    end

    def source_suggestion_supported?(location)
      File.extname(location[:file]).downcase == '.swift' &&
        location[:content].to_s.match?(SWIFT_COMMENT_ARGUMENT_PATTERN)
    end

    def existing_translator_comment_block(location)
      lines = cached_file_lines(location[:file])
      return nil unless lines

      comment_end_index = location[:line] - 2
      return nil if comment_end_index.negative?

      case File.extname(location[:file]).downcase
      when '.strings'
        extract_strings_comment_block(lines, comment_end_index)
      when '.xml'
        extract_xml_comment_block(lines, comment_end_index)
      end
    end

    def extract_strings_comment_block(lines, comment_end_index)
      return nil unless lines[comment_end_index]&.strip&.end_with?('*/')

      comment_start_index = comment_end_index
      comment_start_index -= 1 until comment_start_index.negative? || lines[comment_start_index].include?('/*')
      return nil if comment_start_index.negative?

      {
        start_line: comment_start_index + 1,
        lines: lines[comment_start_index..comment_end_index]
      }
    end

    def extract_xml_comment_block(lines, comment_end_index)
      return nil unless lines[comment_end_index]&.include?('-->')

      comment_start_index = comment_end_index
      comment_start_index -= 1 until comment_start_index.negative? || lines[comment_start_index].include?('<!--')
      return nil if comment_start_index.negative?

      {
        start_line: comment_start_index + 1,
        lines: lines[comment_start_index..comment_end_index]
      }
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

      content.sub(SWIFT_COMMENT_ARGUMENT_PATTERN) { replacement }
    end

    def escape_strings_comment(text)
      text.to_s.gsub('*/', '* /')
    end

    def escape_swift_string(text)
      text
        .to_s
        .gsub('\\') { '\\\\' }
        .gsub('"', '\\"')
        .gsub("\r", '\\r')
        .gsub("\n", '\\n')
        .gsub("\t", '\\t')
    end

    def escape_xml_comment(text)
      text.to_s.gsub('--', '- -')
    end

    def inline_reporting?(inline_mode)
      inline_mode != :none
    end

    def inline_suggestion_mode?(inline_mode)
      %i[translation_suggestion source_suggestion].include?(inline_mode)
    end

    def inline_target_for(inline_mode)
      return :source if %i[source_comment source_suggestion].include?(inline_mode)

      :translation
    end

    def normalize_enum_param(value, valid_values, param_name)
      normalized = value.to_sym if value.respond_to?(:to_sym)
      return normalized if normalized && valid_values.include?(normalized)

      reporter.report(
        message: "Invalid #{param_name} `#{value}`. Expected one of: #{valid_values.join(', ')}.",
        type: :warning
      )
      nil
    end

    def resolve_inline_locations(result, inline_target:, inline_suggestions:, added_lines_by_file:)
      if inline_target == :source
        return build_source_line_locations(
          result,
          inline_suggestions: inline_suggestions,
          added_lines_by_file: added_lines_by_file
        )
      end

      build_translation_line_locations(result)
    end

    def enrich_inline_location(location, added_lines_by_file, inline_suggestions:)
      return location unless inline_suggestions
      return location unless location[:inline_target] == :translation

      comment_block = existing_translator_comment_block(location)
      return location unless comment_block

      added_lines = added_lines_by_file[location[:file]]
      if (comment_block[:start_line]..location[:line]).all? { |line| added_lines.include?(line) }
        location.merge(start_line: comment_block[:start_line])
      else
        location.merge(existing_comment: true)
      end
    end

    def build_translation_line_locations(result)
      Array(result.changed_translation_locations).filter_map do |entry|
        location = parse_result_location(entry)
        next unless location

        lines = cached_file_lines(location[:file])
        next unless lines
        next if location[:line] < 1 || location[:line] > lines.length

        location.merge(content: lines[location[:line] - 1], inline_target: :translation)
      end
    end

    def build_source_line_locations(result, inline_suggestions:, added_lines_by_file:)
      grouped_locations = changed_source_location_groups(result).filter_map do |group|
        locations = Array(group).filter_map do |entry|
          parse_source_location(
            entry,
            inline_suggestions: inline_suggestions,
            added_lines_by_file: added_lines_by_file
          )
        end
        next if locations.empty?

        if inline_suggestions
          locations.first
        else
          locations.find { |location| location[:content].match?(SWIFT_COMMENT_ARGUMENT_PATTERN) } || locations.first
        end
      end

      grouped_locations.uniq { |location| [location[:file], location[:line]] }
    end

    def changed_source_location_groups(result)
      groups = result.changed_location_groups if result.respond_to?(:changed_location_groups)
      return groups if groups&.any?

      Array(result.changed_locations).map { |location| [location] }
    end

    def parse_result_location(entry)
      match = entry.to_s.match(/\A(.+):(\d+)\z/)
      return unless match

      {
        file: match[1],
        line: match[2].to_i
      }
    end

    def parse_source_location(entry, inline_suggestions:, added_lines_by_file:)
      location = parse_result_location(entry)
      return unless location

      file = location[:file]
      line = location[:line]
      lines = cached_file_lines(file)
      return unless lines
      return if line < 1 || line > lines.length

      unless inline_suggestions
        return location.merge(
          content: lines[line - 1],
          inline_target: :source
        )
      end

      comment_line_index = find_swift_comment_line(lines, line - 1)
      return unless comment_line_index

      comment_line = comment_line_index + 1
      return unless added_lines_by_file[file].include?(comment_line)

      {
        file: file,
        line: comment_line,
        content: lines[comment_line_index],
        inline_target: :source
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

    def cached_file_lines(path)
      @file_lines_cache ||= {}
      return @file_lines_cache[path] if @file_lines_cache.key?(path)

      @file_lines_cache[path] = File.exist?(path) ? File.readlines(path).map(&:chomp) : nil
    end

    def report_extraction_errors(results)
      return if results.empty?

      details = results.first(10).map do |result|
        "- `#{result.key}`: #{result.error}"
      end
      details << "- …and #{results.size - 10} more" if results.size > 10
      reporter.report(
        message: "Translation context extraction failed for #{results.size} key(s):\n#{details.join("\n")}",
        type: :warning
      )
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
