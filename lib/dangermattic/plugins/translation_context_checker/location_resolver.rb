# frozen_string_literal: true

module Danger
  # Resolves extractor evidence and Git diff lines into Danger inline locations.
  module TranslationContextCheckerLocationResolver
    private

    def inline_target_files(results, inline_target)
      location_method = inline_target == :source ? :changed_locations : :changed_translation_locations

      results.flat_map { |result| Array(result.public_send(location_method)) }
             .filter_map { |entry| parse_result_location(entry)&.fetch(:file) }
             .uniq
    end

    def build_added_line_map(files)
      map = Hash.new { |hash, key| hash[key] = Set.new }

      files.each do |path|
        each_added_diff_line(path) do |_line, line_number|
          map[path] << line_number
        end
      end

      map
    end

    def each_added_diff_line(path)
      diff = danger.git.diff_for_file(path)
      return unless diff

      new_line_number = nil

      diff.patch.each_line do |line|
        if line.start_with?('diff --git')
          new_line_number = nil
          next
        end

        if (match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          new_line_number = match[1].to_i
          next
        end

        next if new_line_number.nil?
        next if line.start_with?('\\')

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

    def translator_comment_block_containing(location)
      lines = cached_file_lines(location[:file])
      return nil unless lines

      location_index = location[:line] - 1
      return nil if location_index.negative? || location_index >= lines.length

      case File.extname(location[:file]).downcase
      when '.strings'
        comment_block_containing(lines, location_index, opening: '/*', closing: '*/')
      when '.xml'
        comment_block_containing(lines, location_index, opening: '<!--', closing: '-->')
      end
    end

    def comment_block_containing(lines, location_index, opening:, closing:)
      start_index = location_index.downto(0).find { |index| lines[index].include?(opening) }
      return nil unless start_index

      previous_end = location_index.downto(start_index).find { |index| lines[index].include?(closing) }
      return nil if previous_end && previous_end < location_index

      end_index = (location_index...lines.length).find { |index| lines[index].include?(closing) }
      return nil unless end_index

      block = {
        start_line: start_index + 1,
        end_line: end_index + 1,
        lines: lines[start_index..end_index]
      }

      if start_index == end_index
        line = lines[start_index]
        opening_index = line.index(opening)
        closing_index = line.index(closing, opening_index + opening.length)
        if closing_index
          before_comment = line[0...opening_index]
          after_comment = line[(closing_index + closing.length)..].to_s

          block[:comment_only] = before_comment.strip.empty? && after_comment.strip.empty?
          block[:content_without_comment] = before_comment.rstrip if !before_comment.strip.empty? && after_comment.strip.empty?
        end
      end

      block
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
      return location if location[:side] == 'LEFT'

      return enrich_xcstrings_inline_location(location, added_lines_by_file[location[:file]]) if File.extname(location[:file]).downcase == '.xcstrings'

      containing_comment = translator_comment_block_containing(location)
      if containing_comment
        single_added_line = containing_comment[:start_line] == containing_comment[:end_line] &&
                            added_lines_by_file[location[:file]].include?(location[:line])
        if single_added_line
          return location.merge(replace_comment: true) if containing_comment[:comment_only]
          return location.merge(content: containing_comment[:content_without_comment]) if containing_comment[:content_without_comment]
        end

        return location.merge(existing_comment: true)
      end

      comment_block = existing_translator_comment_block(location)
      return location unless comment_block

      added_lines = added_lines_by_file[location[:file]]
      if (comment_block[:start_line]..location[:line]).all? { |line| added_lines.include?(line) }
        location.merge(start_line: comment_block[:start_line])
      else
        location.merge(existing_comment: true)
      end
    end

    def enrich_xcstrings_inline_location(location, added_lines)
      content = location[:content].to_s
      return enrich_xcstrings_comment_location(location, location[:line], content, added_lines) if xcstrings_comment_line?(content)
      return location unless xcstrings_key_line?(content)

      lines = cached_file_lines(location[:file])
      return location unless lines

      body_indexes = xcstrings_body_line_indexes(lines, location[:line], content)
      comment_index = body_indexes.find { |index| xcstrings_comment_line?(lines[index]) }
      if comment_index
        return enrich_xcstrings_comment_location(
          location,
          comment_index + 1,
          lines[comment_index],
          added_lines
        )
      end

      first_child_index = body_indexes.find { |index| !lines[index].strip.empty? }
      child_indentation = if first_child_index
                            lines[first_child_index][/^\s*/].to_s
                          else
                            "#{content[/^\s*/]}  "
                          end
      location.merge(
        insert_comment: true,
        child_indentation: child_indentation,
        trailing_comma: !first_child_index.nil?
      )
    end

    def enrich_xcstrings_comment_location(location, line, content, added_lines)
      return location.merge(existing_comment: true) unless added_lines.include?(line)

      location.merge(line: line, content: content, replace_comment: true)
    end

    def xcstrings_body_line_indexes(lines, key_line, key_content)
      key_indentation_length = key_content[/^\s*/].to_s.length
      (key_line...lines.length).take_while do |index|
        line = lines[index]
        line.strip.empty? || line[/^\s*/].to_s.length > key_indentation_length
      end
    end

    def xcstrings_key_line?(content)
      content.match?(/^\s*"(?:\\.|[^"\\])*"\s*:\s*\{\s*$/)
    end

    def xcstrings_comment_line?(content)
      content.match?(/^\s*"comment"\s*:\s*"(?:\\.|[^"\\])*"\s*,?\s*$/)
    end

    def build_translation_line_locations(result)
      locations = Array(result.changed_translation_locations).filter_map do |entry|
        location = parse_result_location(entry)
        next unless location

        if location[:side] == 'LEFT' && location[:fallback_line]
          location = location.merge(
            line: location[:fallback_line],
            side: 'RIGHT',
            original_side: 'LEFT'
          )
        end

        lines = cached_file_lines(location[:file])
        next location.merge(content: '', inline_target: :translation) if location[:side] == 'LEFT'
        next unless lines && location[:line].between?(1, lines.length)

        location.merge(content: lines[location[:line] - 1], inline_target: :translation)
      end

      locations.uniq do |location|
        [location[:file], location.fetch(:original_side, location[:side])]
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
          locations.find do |location|
            location[:content].match?(self.class::SWIFT_COMMENT_ARGUMENT_PATTERN)
          end || locations.first
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
      if entry.respond_to?(:file) && entry.respond_to?(:line)
        side = entry.respond_to?(:review_side) ? entry.review_side : entry.side.to_s.upcase
        return {
          file: entry.file,
          line: entry.line.to_i,
          side: side,
          fallback_line: (entry.fallback_line if entry.respond_to?(:fallback_line))
        }
      end

      match = entry.to_s.match(/\A(.+):(\d+)\z/)
      return unless match

      {
        file: match[1],
        line: match[2].to_i,
        side: 'RIGHT',
        fallback_line: nil
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
        inline_target: :source,
        side: 'RIGHT'
      }
    end

    def find_swift_comment_line(lines, start_index, lookahead: 8)
      end_index = [lines.length - 1, start_index + lookahead].min

      (start_index..end_index).each do |index|
        line = lines[index]
        return index if line.match?(self.class::SWIFT_COMMENT_ARGUMENT_PATTERN)
        break if index > start_index && line.match?(/^\s*\)\s*,?\s*$/)
      end

      nil
    end

    def cached_file_lines(path)
      @file_lines_cache ||= {}
      return @file_lines_cache[path] if @file_lines_cache.key?(path)

      @file_lines_cache[path] = File.exist?(path) ? File.readlines(path).map(&:chomp) : nil
    end
  end
end
