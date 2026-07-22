# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::TranslationContextChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.translation_context_checker

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
        stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
        stub_const(
          'ExtractionResultStruct',
          Struct.new(
            :key, :text, :description, :ui_element, :tone, :max_length, :locations,
            :changed_locations, :translation_key, :changed_translation_locations, :error,
            keyword_init: true
          )
        )
      end

      def build_extraction_result(**overrides)
        ExtractionResultStruct.new(
          {
            key: 'default_key',
            text: 'Default text',
            description: 'Default description',
            ui_element: nil,
            tone: nil,
            max_length: nil,
            locations: [],
            changed_locations: [],
            translation_key: 'default_key',
            changed_translation_locations: [],
            error: nil
          }.merge(overrides)
        )
      end

      def expect_no_danger_output
        expect(@dangerfile).to not_report
      end

      def status_markdowns
        @dangerfile.status_report[:markdowns]
      end

      def strings_diff(path, added_line:, start_line: 1)
        <<~DIFF
          diff --git a/#{path} b/#{path}
          --- a/#{path}
          +++ b/#{path}
          @@ -#{start_line},1 +#{start_line},2 @@
           "Existing" = "Existing";
          +#{added_line}
        DIFF
      end

      describe '#check_context_suggestions' do
        it 'returns before extraction when all reporting is disabled' do
          allow(@plugin).to receive(:run_extraction)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: 'Localizable.strings',
            inline_mode: :none,
            summary: false
          )

          expect(@plugin).not_to have_received(:run_extraction)
          expect_no_danger_output
        end

        it 'warns about an invalid discovery mode before extraction' do
          allow(@plugin).to receive(:run_extraction)

          @plugin.check_context_suggestions(source_paths: 'Sources', discovery_mode: :both)

          expect(@plugin).not_to have_received(:run_extraction)
          expect(@dangerfile).to report_warnings(
            ['Invalid discovery_mode `both`. Expected one of: auto, translations, source.']
          )
        end

        it 'warns about an invalid inline mode before extraction' do
          allow(@plugin).to receive(:run_extraction)

          @plugin.check_context_suggestions(source_paths: 'Sources', inline_mode: :sideways)

          expect(@plugin).not_to have_received(:run_extraction)
          expect(@dangerfile).to report_warnings(
            ['Invalid inline_mode `sideways`. Expected one of: translation_comment, translation_suggestion, source_comment, source_suggestion, none.']
          )
        end

        it 'warns when source paths are empty' do
          @plugin.check_context_suggestions(source_paths: [])

          expect(@dangerfile).to report_warnings(
            ['source_paths is required for translation context suggestions.']
          )
        end

        it 'warns when source discovery receives translation paths' do
          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: 'Localizable.strings',
            discovery_mode: :source
          )

          expect(@dangerfile).to report_warnings(
            ['translation_paths is not supported when discovery_mode is `source`.']
          )
        end

        it 'warns when translation discovery has no translation paths' do
          @plugin.check_context_suggestions(source_paths: 'Sources', discovery_mode: :translations)

          expect(@dangerfile).to report_warnings(
            ['translation_paths is required when discovery_mode is `translations`.']
          )
        end

        it 'warns when a translation inline mode is used with source discovery' do
          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            discovery_mode: :source,
            inline_mode: :translation_suggestion
          )

          expect(@dangerfile).to report_warnings(
            ['inline_mode `translation_suggestion` is not supported when discovery_mode is `source`.']
          )
        end

        it 'does nothing when no configured file changed' do
          allow(@plugin.git).to receive(:modified_files).and_return(['README.md'])
          allow(@plugin).to receive(:run_extraction)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: 'Localizable.strings'
          )

          expect(@plugin).not_to have_received(:run_extraction)
          expect_no_danger_output
        end

        it 'normalizes ./ source roots before matching changed files' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return([])

          @plugin.check_context_suggestions(source_paths: './Sources/', discovery_mode: :source)

          expect(@plugin).to have_received(:run_extraction).with(
            translation_paths: [],
            source_paths: ['Sources'],
            discovery_mode: :source,
            provider: :anthropic,
            model: nil
          )
        end

        it 'treats a dot source root as the whole repository' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Feature/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return([])

          @plugin.check_context_suggestions(source_paths: '.', discovery_mode: :source)

          expect(@plugin).to have_received(:run_extraction).with(hash_including(source_paths: ['.']))
        end

        it 'prefers one translation-backed extraction in auto mode when both input types changed' do
          translation_path = 'Localizable.strings'
          allow(@plugin.git).to receive(:modified_files).and_return([translation_path, 'Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return([])

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: translation_path
          )

          expect(@plugin).to have_received(:run_extraction).once.with(
            translation_paths: [translation_path],
            source_paths: ['Sources'],
            discovery_mode: :translations,
            provider: :anthropic,
            model: nil
          )
        end

        it 'uses one source-backed extraction in auto mode when only source changed' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return([])

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: 'Localizable.strings'
          )

          expect(@plugin).to have_received(:run_extraction).once.with(
            translation_paths: [],
            source_paths: ['Sources'],
            discovery_mode: :source,
            provider: :anthropic,
            model: nil
          )
        end

        it 'does not switch an explicit translation mode to source mode' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            translation_paths: 'Localizable.strings',
            discovery_mode: :translations
          )

          expect(@plugin).not_to have_received(:run_extraction)
          expect_no_danger_output
        end

        it 'passes provider and model to the extractor' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return([])

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            discovery_mode: :source,
            provider: 'openai',
            model: 'gpt-5-mini'
          )

          expect(@plugin).to have_received(:run_extraction).with(
            hash_including(provider: 'openai', model: 'gpt-5-mini')
          )
        end

        it 'reports an actionable warning when extraction raises' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_raise(I18nContextGenerator::Error, 'missing merge base')

          @plugin.check_context_suggestions(source_paths: 'Sources', discovery_mode: :source)

          expect(@dangerfile).to report_warnings(
            ['Translation context extraction failed: missing merge base']
          )
        end

        it 'reports failed results while preserving successful suggestions' do
          results = [
            build_extraction_result(key: 'failed.key', error: 'API timeout'),
            build_extraction_result(key: 'save.key', description: 'Save button', max_length: 20)
          ]
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return(results)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            discovery_mode: :source,
            inline_mode: :none,
            summary: true
          )

          expect(@dangerfile.status_report[:warnings]).to eq(
            ["Translation context extraction failed for 1 key(s):\n- `failed.key`: API timeout"]
          )
          expect(status_markdowns.map(&:message).join).to include('Save button (Max length: 20)')
        end

        it 'caps extraction error details' do
          results = 12.times.map do |index|
            build_extraction_result(key: "key.#{index}", error: 'API timeout')
          end
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return(results)

          @plugin.check_context_suggestions(source_paths: 'Sources', discovery_mode: :source)

          warning = @dangerfile.status_report[:warnings].first
          expect(
            [warning.include?('failed for 12 key(s)'), warning.include?('- …and 2 more'), warning.include?('key.10')]
          ).to eq([true, true, false])
        end

        it 'filters placeholder results without suppressing valid results' do
          results = [
            build_extraction_result(key: 'missing', description: 'No usage found in source code'),
            build_extraction_result(key: 'save', description: 'Save button')
          ]
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return(results)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            discovery_mode: :source,
            inline_mode: :none,
            summary: true
          )

          table = status_markdowns.first.message
          expect(table).to include('`save`')
          expect(table).not_to include('`missing`')
        end

        context 'with translation inline output' do
          let(:strings_path) { 'Resources/Localizable.strings' }
          let(:strings_content) do
            [
              "\"Existing\" = \"Existing\";\n",
              "\"save.button\" = \"Save\";\n"
            ]
          end
          let(:result) do
            build_extraction_result(
              key: 'save.button',
              text: 'Save',
              description: 'Button that saves the edited settings.',
              max_length: 20,
              locations: ['Sources/Settings.swift:30'],
              changed_translation_locations: ["#{strings_path}:2"]
            )
          end

          before do
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file).with(strings_path).and_return(
              GitDiffStruct.new(
                'modified',
                strings_path,
                strings_diff(strings_path, added_line: '"save.button" = "Save";')
              )
            )
            allow(File).to receive(:exist?).with(strings_path).and_return(true)
            allow(File).to receive(:readlines).with(strings_path).and_return(strings_content)
            allow(@plugin).to receive(:run_extraction).and_return([result])
          end

          it 'posts a native inline comment at the extractor-provided translation line' do
            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: strings_path,
              discovery_mode: :translations
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.message, markdown.file, markdown.line, markdown.start_line]).to eq(
              [
                "**Translation Context Suggestion**\nButton that saves the edited settings.\n*Max length: 20*",
                strings_path,
                2,
                nil
              ]
            )
          end

          it 'builds an apply-ready translation suggestion' do
            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: strings_path,
              discovery_mode: :translations,
              inline_mode: :translation_suggestion
            )

            expect(status_markdowns.fetch(0).message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
              /* Button that saves the edited settings. Max length: 20. */
              "save.button" = "Save";
              ```
            MARKDOWN
          end

          it 'uses each exact extractor-provided translation location' do
            second_path = 'Resources/Other.strings'
            second_result = build_extraction_result(
              key: 'save.button',
              description: 'Save button',
              changed_translation_locations: ["#{strings_path}:2", "#{second_path}:1"]
            )
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path, second_path])
            allow(@plugin.git).to receive(:diff_for_file).with(second_path).and_return(nil)
            allow(File).to receive(:exist?).with(second_path).and_return(true)
            allow(File).to receive(:readlines).with(second_path).and_return(["\"save.button\" = \"Save\";\n"])
            allow(@plugin).to receive(:run_extraction).and_return([second_result])

            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: [strings_path, second_path],
              discovery_mode: :translations
            )

            expect(status_markdowns.map { |markdown| [markdown.file, markdown.line] }).to contain_exactly(
              [strings_path, 2],
              [second_path, 1]
            )
          end

          it 'falls back to the configured report type when no changed location is available' do
            allow(@plugin).to receive(:run_extraction).and_return(
              [build_extraction_result(description: 'Save button')]
            )

            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: strings_path,
              discovery_mode: :translations,
              report_type: :warning
            )

            expect(@dangerfile.status_report[:warnings]).to eq(
              ["**Translation Context Suggestion**\nSave button"]
            )
          end
        end

        context 'with a changed existing translator comment' do
          let(:strings_path) { 'Localizable.strings' }
          let(:description) { 'Button that saves the edited settings.' }
          let(:content) do
            [
              "/*\n",
              " * Old context\n",
              " */\n",
              "\"save.button\" = \"Save\";\n"
            ]
          end
          let(:patch) do
            <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -1,1 +1,4 @@
              +/*
              + * Old context
              + */
              +"save.button" = "Save";
            DIFF
          end

          before do
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file).with(strings_path).and_return(
              GitDiffStruct.new('modified', strings_path, patch)
            )
            allow(File).to receive(:exist?).with(strings_path).and_return(true)
            allow(File).to receive(:readlines).with(strings_path).and_return(content)
            allow(@plugin).to receive(:run_extraction).and_return(
              [
                build_extraction_result(
                  key: 'save.button',
                  description: description,
                  changed_translation_locations: ["#{strings_path}:4"]
                )
              ]
            )
          end

          it 'uses Danger 9.6 native ranged Markdown for a replaceable comment block' do
            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: strings_path,
              discovery_mode: :translations,
              inline_mode: :translation_suggestion
            )

            markdown = status_markdowns.fetch(0)
            expect(
              [markdown.message, markdown.file, markdown.line, markdown.start_line, markdown.side, markdown.start_side]
            ).to eq(
              [
                <<~MARKDOWN.chomp,
                  ```suggestion
                  /* Button that saves the edited settings. */
                  "save.button" = "Save";
                  ```
                MARKDOWN
                strings_path,
                4,
                1,
                'RIGHT',
                'RIGHT'
              ]
            )
          end

          it 'uses plain text when the existing comment is not fully in added lines' do
            allow(@plugin.git).to receive(:diff_for_file).with(strings_path).and_return(
              GitDiffStruct.new(
                'modified',
                strings_path,
                <<~DIFF
                  diff --git a/#{strings_path} b/#{strings_path}
                  --- a/#{strings_path}
                  +++ b/#{strings_path}
                  @@ -1,4 +1,4 @@
                   /*
                    * Old context
                   */
                  -"save.button" = "Old";
                  +"save.button" = "Save";
                DIFF
              )
            )

            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              translation_paths: strings_path,
              discovery_mode: :translations,
              inline_mode: :translation_suggestion
            )

            markdown = status_markdowns.fetch(0)
            expect(
              [
                markdown.message.include?('**Translation Context Suggestion**'),
                markdown.message.include?('```suggestion'),
                markdown.start_line
              ]
            ).to eq([true, false, nil])
          end
        end

        context 'with an Android collection child' do
          let(:xml_path) { 'app/src/main/res/values/strings.xml' }

          before do
            allow(@plugin.git).to receive(:modified_files).and_return([xml_path])
            allow(@plugin.git).to receive(:diff_for_file).with(xml_path).and_return(nil)
            allow(File).to receive(:exist?).with(xml_path).and_return(true)
            allow(File).to receive(:readlines).with(xml_path).and_return(
              [
                "<resources>\n",
                "  <plurals name=\"item_count\">\n",
                "    <item quantity=\"one\">%d item</item>\n",
                "  </plurals>\n",
                "</resources>\n"
              ]
            )
            allow(@plugin).to receive(:run_extraction).and_return(
              [
                build_extraction_result(
                  key: 'item_count:one',
                  translation_key: 'item_count',
                  description: 'Singular item count.',
                  changed_translation_locations: ["#{xml_path}:3"]
                )
              ]
            )
          end

          it 'posts on the exact changed item line supplied by the extractor' do
            @plugin.check_context_suggestions(
              source_paths: 'app/src/main/java',
              translation_paths: xml_path,
              discovery_mode: :translations
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.file, markdown.line]).to eq([xml_path, 3])
            expect(markdown.message).to include('Singular item count.')
          end
        end

        context 'with source inline output' do
          let(:source_path) { 'Sources/SettingsView.swift' }
          let(:source_content) do
            [
              "struct SettingsView {\n",
              "  let title = String(localized: \"settings.title\",\n",
              "                     comment: \"\")\n",
              "}\n"
            ]
          end
          let(:source_patch) do
            <<~DIFF
              diff --git a/#{source_path} b/#{source_path}
              --- a/#{source_path}
              +++ b/#{source_path}
              @@ -1,3 +1,4 @@
               struct SettingsView {
              +  let title = String(localized: "settings.title",
              +                     comment: "")
               }
            DIFF
          end
          let(:result) do
            build_extraction_result(
              key: 'settings.title',
              description: 'Title for the settings screen.',
              locations: ["#{source_path}:2", 'Sources/Other.swift:8'],
              changed_locations: ["#{source_path}:2"]
            )
          end

          before do
            allow(@plugin.git).to receive(:modified_files).and_return([source_path])
            allow(@plugin.git).to receive(:diff_for_file).with(source_path).and_return(
              GitDiffStruct.new('modified', source_path, source_patch)
            )
            allow(File).to receive(:exist?).with(source_path).and_return(true)
            allow(File).to receive(:readlines).with(source_path).and_return(source_content)
            allow(@plugin).to receive(:run_extraction).and_return([result])
          end

          it 'comments only on changed evidence, not every usage location' do
            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              discovery_mode: :source,
              inline_mode: :source_comment
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.file, markdown.line]).to eq([source_path, 2])
            expect(markdown.message).to include('Title for the settings screen.')
          end

          it 'offers a Swift comment suggestion on an added comment line' do
            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              discovery_mode: :source,
              inline_mode: :source_suggestion
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.file, markdown.line]).to eq([source_path, 3])
            expect(markdown.message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
                                   comment: "Title for the settings screen.")
              ```
            MARKDOWN
          end

          it 'falls back to a PR-level report when the comment line is unchanged' do
            allow(@plugin.git).to receive(:diff_for_file).with(source_path).and_return(
              GitDiffStruct.new(
                'modified',
                source_path,
                <<~DIFF
                  diff --git a/#{source_path} b/#{source_path}
                  --- a/#{source_path}
                  +++ b/#{source_path}
                  @@ -1,3 +1,3 @@
                   struct SettingsView {
                  -  let title = String(localized: "old.title",
                  +  let title = String(localized: "settings.title",
                                       comment: "")
                DIFF
              )
            )

            @plugin.check_context_suggestions(
              source_paths: 'Sources',
              discovery_mode: :source,
              inline_mode: :source_suggestion,
              report_type: :warning
            )

            expect(status_markdowns).to be_empty
            expect(@dangerfile.status_report[:warnings]).to eq(
              ["**Translation Context Suggestion**\nTitle for the settings screen."]
            )
          end
        end

        it 'escapes summary table cells and sorts keys' do
          results = [
            build_extraction_result(key: 'z|key', text: "First\nline", description: 'Z description'),
            build_extraction_result(key: 'a.key', text: 'A', description: 'A|description')
          ]
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return(results)

          @plugin.check_context_suggestions(
            source_paths: 'Sources',
            discovery_mode: :source,
            inline_mode: :none,
            summary: true
          )

          table = status_markdowns.fetch(0).message
          expect(
            [
              table.index('`a.key`') < table.index('`z\\|key`'),
              table.include?('A\\|description'),
              table.include?('First line')
            ]
          ).to eq([true, true, true])
        end
      end

      describe '#run_extraction' do
        it 'passes the explicit Danger diff range and normalized API values to the extractor' do
          config = instance_double(I18nContextGenerator::Config)
          extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, results: [:result])

          allow(Danger::EnvironmentManager).to receive_messages(
            danger_base_branch: 'danger_base',
            danger_head_branch: 'danger_head'
          )
          allow(I18nContextGenerator::Config).to receive(:new).and_return(config)
          allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

          results = @plugin.send(
            :run_extraction,
            translation_paths: ['Localizable.strings'],
            source_paths: ['Sources'],
            discovery_mode: :translations,
            provider: :openai,
            model: 'gpt-5-mini'
          )

          expect(I18nContextGenerator::Config).to have_received(:new).with(
            translations: ['Localizable.strings'],
            source_paths: ['Sources'],
            discovery_mode: :translations,
            provider: :openai,
            model: 'gpt-5-mini',
            no_cache: true,
            diff_base: 'danger_base',
            diff_head: 'danger_head'
          )
          expect(results).to eq([:result])
        end
      end

      describe '#each_added_diff_line' do
        it 'tracks new-file line numbers across additions, removals, and context' do
          path = 'Sources/View.swift'
          patch = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -8,3 +8,4 @@
             line eight
            -old line
            +new line
            +another line
             last line
          DIFF
          allow(@plugin.danger.git).to receive(:diff_for_file).with(path).and_return(
            GitDiffStruct.new('modified', path, patch)
          )

          added = []
          @plugin.send(:each_added_diff_line, path) { |line, number| added << [line.chomp, number] }

          expect(added).to eq([['+new line', 9], ['+another line', 10]])
        end
      end

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
      end
    end
  end
end
