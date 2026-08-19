# frozen_string_literal: true

require_relative 'spec_helper'
require_relative 'support/translation_context_checker_context'

module Danger
  describe Danger::TranslationContextChecker do
    describe 'with Dangerfile' do
      include_context 'with translation context checker'

      describe 'suggestion escaping' do
        it 'escapes Swift string content' do
          result = build_extraction_result(description: "A \"quoted\" path \\ value\nnext")
          updated = @plugin.send(
            :format_source_inline_suggestion,
            result,
            file: 'Sources/View.swift',
            content: 'comment: "")'
          )

          expect(updated).to include('comment: "A \\"quoted\\" path \\\\ value\\nnext")')
        end

        it 'prevents invalid XML comment sequences' do
          result = build_extraction_result(description: 'Before -- after')
          comment = @plugin.send(
            :translator_comment_for,
            result,
            file: 'strings.xml',
            content: '  <string name="key">Value</string>'
          )

          expect(comment).to eq('  <!-- Before - - after -->')
        end

        it 'normalizes multiline text and code fences before rendering a translator comment' do
          result = build_extraction_result(description: "First line\n```suggestion\n@reviewer second line")
          comment = @plugin.send(
            :translator_comment_for,
            result,
            file: 'Localizable.strings',
            content: '"key" = "Value";'
          )

          expect(comment).to eq("/* First line '''suggestion @reviewer second line */")
        end
      end
    end
  end
end
