# frozen_string_literal: true

require 'json'

module Danger
  # Format-specific inline suggestion rendering.
  module TranslationContextCheckerSuggestionRenderer
    private

    def format_inline_message(result, location: nil, inline_suggestions: false)
      if inline_suggestions
        suggestion = format_inline_suggestion(result, location)
        return suggestion if suggestion
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

      return format_xcstrings_inline_suggestion(result, location) if File.extname(location[:file]).downcase == '.xcstrings'
      return unless translation_suggestion_supported?(location)

      comment_line = translator_comment_for(result, location)
      return unless comment_line

      if location[:replace_comment]
        return [
          '```suggestion',
          comment_line,
          '```'
        ].join("\n")
      end

      [
        '```suggestion',
        comment_line,
        location[:content],
        '```'
      ].join("\n")
    end

    def format_xcstrings_inline_suggestion(result, location)
      content = location[:content].to_s
      return if content.strip.empty?
      return if location[:existing_comment]

      inserting_comment = location[:insert_comment]
      return unless inserting_comment || location[:replace_comment]

      indentation = inserting_comment ? location[:child_indentation] : content[/^\s*/].to_s
      return unless indentation

      comment_value = JSON.generate(single_line_suggestion_comment_text(result))
      comment_line = "#{indentation}\"comment\" : #{comment_value}"
      trailing_comma = inserting_comment ? location[:trailing_comma] : content.rstrip.end_with?(',')
      comment_line += ',' if trailing_comma

      lines = ['```suggestion']
      lines << content if inserting_comment
      lines << comment_line
      lines << '```'
      lines.join("\n")
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
        location[:content].to_s.match?(self.class::SWIFT_COMMENT_ARGUMENT_PATTERN)
    end

    def translator_comment_for(result, location)
      indentation = location[:content][/^\s*/] || ''
      comment_text = single_line_suggestion_comment_text(result)

      case File.extname(location[:file]).downcase
      when '.strings'
        "#{indentation}/* #{escape_strings_comment(comment_text)} */"
      when '.xml'
        "#{indentation}<!-- #{escape_xml_comment(comment_text)} -->"
      end
    end

    def suggestion_comment_text(result)
      description = result.description.to_s.gsub(/`{3,}/) { |ticks| "'" * ticks.length }
      return description unless result.max_length

      "#{description} Max length: #{result.max_length}."
    end

    def single_line_suggestion_comment_text(result)
      suggestion_comment_text(result).gsub(/\s+/, ' ').strip
    end

    def update_swift_comment_argument(content, comment_text)
      replacement = "comment: \"#{escape_swift_string(comment_text)}\""

      content.sub(self.class::SWIFT_COMMENT_ARGUMENT_PATTERN) { replacement }
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
  end
end
