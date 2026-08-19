# frozen_string_literal: true

require_relative 'spec_helper'
require_relative 'support/translation_context_checker_context'

module Danger
  describe Danger::TranslationContextChecker do
    describe 'with Dangerfile' do
      include_context 'with translation context checker'

      describe 'typed translation diff locations' do
        let(:strings_path) { 'Resources/Localizable.strings' }

        before do
          allow(@plugin).to receive(:build_added_line_map).and_return(
            strings_path => Set.new,
            'Resources/Localizable.xcstrings' => Set.new
          )
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:readlines).and_call_original
        end

        it 'uses the head fallback for a removed-side translation suggestion' do
          allow(File).to receive(:exist?).with(strings_path).and_return(true)
          allow(File).to receive(:readlines).with(strings_path).and_return(
            ["\"save.button\" = \"Save\";\n"]
          )
          result = build_extraction_result(
            key: 'save.button',
            description: 'Button that saves changes.',
            changed_translation_locations: [
              I18nContextGenerator::ChangedLocation.new(
                file: strings_path,
                line: 1,
                side: :left,
                fallback_line: 1
              )
            ]
          )

          @plugin.send(
            :post_inline_comments,
            [result],
            :message,
            inline_mode: :translation_suggestion
          )

          markdown = status_markdowns.fetch(0)
          expect([markdown.file, markdown.line, markdown.side]).to eq(
            [strings_path, 1, nil]
          )
          expect(markdown.message).to include(
            '```suggestion',
            '/* Button that saves changes. */',
            '"save.button" = "Save";'
          )
        end

        it 'reports plain PR-level feedback when no head fallback exists' do
          result = build_extraction_result(
            key: 'removed.key',
            description: 'Removed translation context.',
            changed_translation_locations: [
              I18nContextGenerator::ChangedLocation.new(
                file: strings_path,
                line: 4,
                side: :left
              )
            ]
          )

          @plugin.send(
            :post_inline_comments,
            [result],
            :warning,
            inline_mode: :translation_suggestion
          )

          expect(status_markdowns).to be_empty
          expect(@dangerfile.status_report[:warnings]).to eq(
            ["**Translation Context Suggestion**\nRemoved translation context."]
          )
        end

        it 'deduplicates residual left reports while publishing right locations' do
          allow(File).to receive(:exist?).with(strings_path).and_return(true)
          allow(File).to receive(:readlines).with(strings_path).and_return(
            ["\"removed.key\" = \"Removed\";\n"]
          )
          result = build_extraction_result(
            key: 'removed.key',
            description: 'Removed translation context.',
            changed_translation_locations: [
              I18nContextGenerator::ChangedLocation.new(
                file: strings_path,
                line: 4,
                side: :left
              ),
              I18nContextGenerator::ChangedLocation.new(
                file: strings_path,
                line: 5,
                side: :left
              ),
              I18nContextGenerator::ChangedLocation.new(
                file: strings_path,
                line: 1,
                side: :right
              )
            ]
          )

          @plugin.send(
            :post_inline_comments,
            [result],
            :warning,
            inline_mode: :translation_comment
          )

          expect(@dangerfile.status_report[:warnings]).to eq(
            ["**Translation Context Suggestion**\nRemoved translation context."]
          )
          expect(status_markdowns.map { |markdown| [markdown.file, markdown.line] }).to eq(
            [[strings_path, 1]]
          )
        end

        it 'publishes separate results from the same translation file' do
          allow(File).to receive(:exist?).with(strings_path).and_return(true)
          allow(File).to receive(:readlines).with(strings_path).and_return(
            %w[first second third fourth]
          )
          results = [
            build_extraction_result(
              key: 'first.key',
              description: 'First description.',
              changed_translation_locations: [
                I18nContextGenerator::ChangedLocation.new(file: strings_path, line: 2, side: :right)
              ]
            ),
            build_extraction_result(
              key: 'second.key',
              description: 'Second description.',
              changed_translation_locations: [
                I18nContextGenerator::ChangedLocation.new(file: strings_path, line: 4, side: :right)
              ]
            )
          ]

          @plugin.send(
            :post_inline_comments,
            results,
            :message,
            inline_mode: :translation_comment
          )

          expect(status_markdowns.map { |markdown| [markdown.file, markdown.line, markdown.message] }).to eq(
            [
              [strings_path, 2, "**Translation Context Suggestion**\nFirst description."],
              [strings_path, 4, "**Translation Context Suggestion**\nSecond description."]
            ]
          )
        end

        it 'builds one apply-ready inline suggestion per string-catalog key' do
          catalog_path = 'Resources/Localizable.xcstrings'
          catalog_lines = [
            "{\n",
            "  \"strings\": {\n",
            "    \"settings.title\": {\n",
            "    }\n",
            "  }\n",
            "}\n"
          ]
          stub_xcstrings_catalog(catalog_path, catalog_lines)

          markdown = post_xcstrings_suggestion(
            catalog_path,
            description: 'Settings screen title.',
            lines: [3, 4]
          )

          parsed = parse_applied_suggestion(catalog_lines, markdown)
          expect([markdown.message, markdown.file, markdown.line, parsed.dig('strings', 'settings.title', 'comment')]).to eq(
            [
              <<~MARKDOWN.chomp,
                ```suggestion
                    "settings.title": {
                      "comment" : "Settings screen title."
                ```
              MARKDOWN
              catalog_path,
              3,
              'Settings screen title.'
            ]
          )
        end

        it 'replaces an existing string-catalog comment with JSON-encoded text' do
          catalog_path = 'Resources/Localizable.xcstrings'
          catalog_lines = [
            "{\n",
            "  \"strings\": {\n",
            "    \"settings.title\" : {\n",
            "      \"comment\" : \"Old context\",\n",
            "      \"localizations\" : {}\n",
            "    }\n",
            "  }\n",
            "}\n"
          ]
          stub_xcstrings_catalog(catalog_path, catalog_lines)

          markdown = post_xcstrings_suggestion(
            catalog_path,
            description: 'Settings "home" screen title.'
          )

          parsed = parse_applied_suggestion(catalog_lines, markdown)
          expect([markdown.message, markdown.file, markdown.line, parsed.dig('strings', 'settings.title', 'comment')]).to eq(
            [
              <<~MARKDOWN.chomp,
                ```suggestion
                      "comment" : "Settings \\"home\\" screen title.",
                ```
              MARKDOWN
              catalog_path,
              4,
              'Settings "home" screen title.'
            ]
          )
        end

        it 'adds a comma when inserting before existing string-catalog members' do
          catalog_path = 'Resources/Localizable.xcstrings'
          catalog_lines = [
            "{\n",
            "  \"strings\": {\n",
            "    \"settings.title\" : {\n",
            "      \"extractionState\" : \"manual\"\n",
            "    }\n",
            "  }\n",
            "}\n"
          ]
          stub_xcstrings_catalog(catalog_path, catalog_lines)

          markdown = post_xcstrings_suggestion(
            catalog_path,
            description: 'Settings screen title.'
          )

          parsed = parse_applied_suggestion(catalog_lines, markdown)
          expect(markdown.message).to include('"comment" : "Settings screen title.",')
          expect(
            [parsed.dig('strings', 'settings.title', 'comment'),
             parsed.dig('strings', 'settings.title', 'extractionState')]
          ).to eq(['Settings screen title.', 'manual'])
        end

        it 'uses plain text when an existing string-catalog comment is outside the diff' do
          catalog_path = 'Resources/Localizable.xcstrings'
          catalog_lines = [
            "{\n",
            "  \"strings\": {\n",
            "    \"settings.title\" : {\n",
            "      \"comment\" : \"Old context\"\n",
            "    }\n",
            "  }\n",
            "}\n"
          ]
          patch = <<~DIFF
            diff --git a/#{catalog_path} b/#{catalog_path}
            --- a/#{catalog_path}
            +++ b/#{catalog_path}
            @@ -3,2 +3,2 @@
            -    "old.title" : {
            +    "settings.title" : {
                   "comment" : "Old context"
          DIFF
          stub_xcstrings_catalog(catalog_path, catalog_lines, patch: patch)

          markdown = post_xcstrings_suggestion(
            catalog_path,
            description: 'Settings screen title.'
          )

          expect([markdown.message, markdown.file, markdown.line]).to eq(
            [
              "**Translation Context Suggestion**\nSettings screen title.",
              catalog_path,
              3
            ]
          )
        end

        it 'finds a changed existing comment despite ragged indentation' do
          catalog_path = 'Resources/Localizable.xcstrings'
          catalog_lines = [
            "{\n",
            "  \"strings\": {\n",
            "    \"settings.title\" : {\n",
            "      \"localizations\" : {},\n",
            "        \"comment\" : \"Old context\"\n",
            "    }\n",
            "  }\n",
            "}\n"
          ]
          stub_xcstrings_catalog(catalog_path, catalog_lines)

          markdown = post_xcstrings_suggestion(
            catalog_path,
            description: 'Settings screen title.'
          )

          parsed = parse_applied_suggestion(catalog_lines, markdown)
          expect(
            [
              markdown.line,
              markdown.message,
              parsed.dig('strings', 'settings.title', 'comment')
            ]
          ).to eq(
            [
              5,
              <<~MARKDOWN.chomp,
                ```suggestion
                        "comment" : "Settings screen title."
                ```
              MARKDOWN
              'Settings screen title.'
            ]
          )
        end

        it 'posts results in deterministic file and key order' do
          allow(File).to receive(:exist?).with('Resources/A.strings').and_return(true)
          allow(File).to receive(:exist?).with('Resources/Z.strings').and_return(true)
          allow(File).to receive(:readlines).with('Resources/A.strings').and_return(
            ["\"a.key\" = \"A\";\n"]
          )
          allow(File).to receive(:readlines).with('Resources/Z.strings').and_return(
            ["\"z.key\" = \"Z\";\n"]
          )
          results = [
            build_extraction_result(
              key: 'z.key',
              source_file: 'Resources/Z.strings',
              changed_translation_locations: ['Resources/Z.strings:1']
            ),
            build_extraction_result(
              key: 'a.key',
              source_file: 'Resources/A.strings',
              changed_translation_locations: ['Resources/A.strings:1']
            )
          ]

          @plugin.send(
            :post_inline_comments,
            results,
            :message,
            inline_mode: :translation_comment
          )

          expect(status_markdowns.map(&:file)).to eq(
            ['Resources/A.strings', 'Resources/Z.strings']
          )
        end
      end

      describe '#build_added_line_map' do
        it 'uses the Danger diff range with the generator changed-lines API', :aggregate_failures do
          changed_lines = { 'Sources/View.swift' => Set[9, 10] }
          git_diff = instance_double(I18nContextGenerator::GitDiff, changed_lines: changed_lines)
          allow(I18nContextGenerator::GitDiff).to receive(:new).and_return(git_diff)

          result = @plugin.send(:build_added_line_map, ['Sources/View.swift'])

          expect(I18nContextGenerator::GitDiff).to have_received(:new).with(
            base_ref: 'danger_base',
            head_ref: 'danger_head'
          )
          expect(git_diff).to have_received(:changed_lines).with(['Sources/View.swift'])
          expect(result).to eq(changed_lines)
        end

        it 'keeps the generator contract for added lines that begin with a plus' do
          path = 'Sources/View.swift'
          patch = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -1,1 +1,4 @@
             first
            +++ shell style marker
            +second added
            +third added
          DIFF
          allow(File).to receive(:exist?).with(path).and_return(true)
          git_diff = I18nContextGenerator::GitDiff.new(base_ref: 'danger_base', head_ref: 'danger_head')
          allow(git_diff).to receive(:git_diff_for_path).with(path).and_return(patch)
          allow(I18nContextGenerator::GitDiff).to receive(:new).and_return(git_diff)

          result = @plugin.send(:build_added_line_map, [path])

          expect(result).to eq(path => Set[2, 3, 4])
        end
      end
    end
  end
end
