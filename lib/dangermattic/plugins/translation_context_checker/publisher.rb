# frozen_string_literal: true

module Danger
  # Deterministic Danger comment and summary publication.
  module TranslationContextCheckerPublisher
    private

    def post_inline_comments(results, report_type, inline_mode:)
      inline_suggestions = inline_suggestion_mode?(inline_mode)
      inline_target = inline_target_for(inline_mode)
      added_lines_by_file = if inline_suggestions
                              build_added_line_map(inline_target_files(results, inline_target))
                            else
                              Hash.new { |hash, key| hash[key] = Set.new }
                            end

      sorted_results(results).each do |result|
        locations = resolve_inline_locations(
          result,
          inline_target: inline_target,
          inline_suggestions: inline_suggestions,
          added_lines_by_file: added_lines_by_file
        )

        if locations&.any?
          post_result_locations(
            result,
            locations,
            added_lines_by_file,
            inline_suggestions: inline_suggestions,
            report_type: report_type
          )
        else
          reporter.report(message: format_inline_message(result), type: report_type)
        end
      end
    end

    def post_result_locations(result, locations, added_lines_by_file, inline_suggestions:, report_type:)
      reported_left_fallback = false

      locations.sort_by { |location| inline_location_sort_key(location) }.each do |location|
        location = enrich_inline_location(
          location,
          added_lines_by_file,
          inline_suggestions: inline_suggestions
        )
        comment = format_inline_message(result, location: location, inline_suggestions: inline_suggestions)
        next if comment.to_s.empty?

        if location[:side] == 'LEFT'
          next if reported_left_fallback

          reporter.report(message: comment, type: report_type)
          reported_left_fallback = true
        else
          post_inline_markdown(comment, location)
        end
      end
    end

    def post_inline_markdown(comment, location)
      options = { file: location[:file], line: location[:line] }
      options[:side] = location[:side] if location[:side] == 'LEFT'
      if location[:start_line]
        options.merge!(
          start_line: location[:start_line],
          side: location.fetch(:side, 'RIGHT'),
          start_side: location.fetch(:side, 'RIGHT')
        )
      end
      markdown(comment, **options)
    end

    def post_summary_table(results)
      table = "### Translation Context Suggestions\n\n"
      table += "| Translation file | Key | Text | Suggested Context |\n"
      table += "|------------------|-----|------|-------------------|\n"

      sorted_results(results).each do |result|
        source_file = escape_table_cell(result_source_file(result))
        key = escape_table_cell(result.key)
        text = escape_table_cell(truncate(result.text.to_s, 50))
        desc = escape_table_cell(format_summary_description(result))
        table += "| #{source_file} | `#{key}` | #{text} | #{desc} |\n"
      end

      markdown(table)
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

    def sorted_results(results)
      results.sort_by do |result|
        [
          result_source_file(result),
          result.respond_to?(:translation_key) ? result.translation_key.to_s : '',
          result.key.to_s
        ]
      end
    end

    def result_source_file(result)
      result.respond_to?(:source_file) ? result.source_file.to_s : ''
    end

    def inline_location_sort_key(location)
      [
        location[:file].to_s,
        location.fetch(:side, 'RIGHT'),
        location[:line].to_i
      ]
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
