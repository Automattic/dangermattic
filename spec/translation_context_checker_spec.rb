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
        stub_const('ExtractionResultStruct', Struct.new(:key, :text, :description, :ui_element, :tone, :max_length,
                                                        :locations, :error, keyword_init: true))
      end

      def expect_no_danger_output
        expect(@dangerfile).to not_report
        expect(@dangerfile.status_report[:markdowns]).to be_empty
      end

      def expect_plain_text_translation_suggestion
        expect(@dangerfile.status_report[:markdowns].map(&:message)).to contain_exactly(
          satisfy('plain text suggestion') do |message|
            message.include?('**Translation Context Suggestion**') &&
              !message.include?('```suggestion')
          end
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
            error: nil
          }.merge(overrides)
        )
      end

      shared_examples 'an invalid option warning' do |method_args:, warning:|
        it "warns for #{method_args.keys.last} without loading txcontext" do
          allow(@plugin).to receive(:load_txcontext)

          @plugin.check_context_suggestions(
            translations: 'Localizable.strings',
            source_paths: ['Sources/'],
            **method_args
          )

          expect(@plugin).not_to have_received(:load_txcontext)
          expect(@dangerfile.status_report.slice(:warnings, :errors, :messages, :markdowns)).to eq(
            warnings: [warning],
            errors: [],
            messages: [],
            markdowns: []
          )
        end
      end

      shared_examples 'a skipped extraction result' do |description, result_attributes|
        it description do
          allow(@plugin).to receive(:run_extraction).and_return([ExtractionResultStruct.new(**result_attributes)])

          @plugin.check_context_suggestions(
            translations: strings_path,
            source_paths: ['Sources/']
          )

          expect_no_danger_output
        end
      end

      shared_examples 'a key line map example' do |path:, content:, expected_locations:|
        it "maps keys for #{path}" do
          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:readlines).with(path).and_return(content)

          result = @plugin.send(:build_key_line_map, [path])

          expected_locations.each do |key, locations|
            expect(result[key]).to eq(locations)
          end
        end
      end

      describe '#check_context_suggestions' do
        context 'when txcontext gem is not available' do
          before do
            allow(@plugin).to receive(:load_txcontext).and_return(false)
          end

          it 'reports a warning about missing gem' do
            @plugin.check_context_suggestions(
              translations: 'Localizable.strings',
              source_paths: ['Sources/']
            )

            expect(@dangerfile).to report_warnings(
              ['`txcontext` gem is required for translation context suggestions. Add it to your Gemfile.']
            )
          end
        end

        context 'when no translation files are changed' do
          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
          end

          it 'does nothing when translation file is not in the PR diff' do
            allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])

            @plugin.check_context_suggestions(
              translations: 'Localizable.strings',
              source_paths: ['Sources/']
            )

            expect_no_danger_output
          end
        end

        context 'when reporting is disabled' do
          it 'returns without loading txcontext when inline output and summary are both disabled' do
            allow(@plugin).to receive(:load_txcontext)

            @plugin.check_context_suggestions(
              translations: 'Localizable.strings',
              source_paths: ['Sources/'],
              inline_mode: :none,
              summary: false
            )

            expect(@plugin).not_to have_received(:load_txcontext)
            expect_no_danger_output
          end
        end

        context 'when an option value is invalid' do
          it_behaves_like 'an invalid option warning',
                          method_args: { inline_mode: :sideways },
                          warning: 'Invalid inline_mode `sideways`. Expected one of: translation_comment, translation_suggestion, source_comment, source_suggestion, none.'
        end

        context 'when .strings file is changed' do
          let(:strings_path) { 'WooCommerce/Resources/en.lproj/Localizable.strings' }
          let(:strings_diff) do
            <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              index abc1234..def5678 100644
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -100,3 +100,5 @@
               "Existing Key" = "Existing Value";
              +"Add a tracking" = "Add a tracking";
              +"Save changes" = "Save changes";
            DIFF
          end

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, strings_diff))
          end

          it 'extracts added keys from the diff' do
            changed_keys = @plugin.send(:extract_changed_keys, [strings_path])

            expect(changed_keys).to contain_exactly('Add a tracking', 'Save changes')
          end

          it 'does not extract removed or context lines as keys' do
            diff_with_removal = <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -1,3 +1,3 @@
               "Unchanged" = "Value";
              -"Removed Key" = "Old Value";
              +"New Key" = "New Value";
            DIFF

            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, diff_with_removal))

            changed_keys = @plugin.send(:extract_changed_keys, [strings_path])

            expect(changed_keys).to contain_exactly('New Key')
          end
        end

        context 'when strings.xml file is changed' do
          let(:xml_path) { 'app/src/main/res/values/strings.xml' }
          let(:xml_diff) do
            <<~DIFF
              diff --git a/#{xml_path} b/#{xml_path}
              --- a/#{xml_path}
              +++ b/#{xml_path}
              @@ -1,3 +1,6 @@
               <resources>
              +  <string name="add_tracking">Add a tracking</string>
              +  <string-array name="sort_options">
              +  <plurals name="item_count">
               </resources>
            DIFF
          end

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([xml_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(xml_path)
              .and_return(GitDiffStruct.new('modified', xml_path, xml_diff))
          end

          it 'extracts string, string-array, and plurals keys from the diff' do
            changed_keys = @plugin.send(:extract_changed_keys, [xml_path])

            expect(changed_keys).to contain_exactly('add_tracking', 'sort_options', 'item_count')
          end
        end

        context 'when XML tags have reordered attributes' do
          let(:xml_path) { 'app/src/main/res/values/strings.xml' }
          let(:xml_diff) do
            <<~DIFF
              diff --git a/#{xml_path} b/#{xml_path}
              --- a/#{xml_path}
              +++ b/#{xml_path}
              @@ -1,3 +1,6 @@
               <resources>
              +  <string formatted="false" name="format_key">Value</string>
              +  <plurals translatable="false" name="count_key">
              +  <string-array tools:ignore="foo" name="array_key">
               </resources>
            DIFF
          end

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([xml_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(xml_path)
              .and_return(GitDiffStruct.new('modified', xml_path, xml_diff))
          end

          it 'extracts keys regardless of attribute order' do
            changed_keys = @plugin.send(:extract_changed_keys, [xml_path])

            expect(changed_keys).to contain_exactly('format_key', 'count_key', 'array_key')
          end
        end

        context 'when extraction runs successfully' do
          let(:strings_path) { 'WooCommerce/Resources/en.lproj/Localizable.strings' }
          let(:strings_diff) do
            <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -1,2 +1,3 @@
               "Existing" = "Existing";
              +"Add a tracking" = "Add a tracking";
            DIFF
          end
          let(:strings_content) do
            <<~STRINGS
              "Existing" = "Existing";
              "Add a tracking" = "Add a tracking";
            STRINGS
          end
          let(:source_paths) { ['WooCommerce/'] }
          let(:suggested_context) do
            'Button label in the order detail screen that initiates shipment tracking setup.'
          end
          let(:translation_suggestion_markdown) do
            <<~MESSAGE.chomp
              ```suggestion
              /* #{suggested_context} */
              "Add a tracking" = "Add a tracking";
              ```
            MESSAGE
          end

          let(:mock_result) do
            build_extraction_result(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: suggested_context,
              ui_element: 'button',
              tone: 'neutral',
              locations: ['OrderDetailViewController.swift:42']
            )
          end

          before do
            allow(@plugin).to receive_messages(load_txcontext: true, run_extraction: [mock_result])
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, strings_diff))
            allow(File).to receive(:exist?).with(strings_path).and_return(true)
            allow(File).to receive(:readlines).with(strings_path).and_return(strings_content.lines)
          end

          def check_strings_context(**kwargs)
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: source_paths,
              **kwargs
            )
          end

          it 'posts inline message with context suggestion' do
            check_strings_context

            expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq(
              ["**Translation Context Suggestion**\n#{suggested_context}"]
            )
          end

          it 'posts a summary markdown table' do
            check_strings_context(inline_mode: :none, summary: true)

            expect(@dangerfile.status_report[:markdowns].first.message).to eq(<<~MARKDOWN)
              ### Translation Context Suggestions

              | Key | Text | Suggested Context |
              |-----|------|-------------------|
              | `Add a tracking` | Add a tracking | #{suggested_context} |
            MARKDOWN
          end

          it 'can include a GitHub suggestion block in inline comments' do
            check_strings_context(inline_mode: :translation_suggestion)

            expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq([translation_suggestion_markdown])
          end

          it 'falls back to the translation file when source suggestions cannot resolve a Swift comment line' do
            source_path = 'OrderDetailViewController.swift'
            source_result = build_extraction_result(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: suggested_context,
              ui_element: 'button',
              tone: 'neutral',
              locations: ["#{source_path}:1"]
            )
            source_content = [
              "static let first = NSLocalizedString(\n",
              "    \"first\",\n",
              ")\n",
              "static let second = NSLocalizedString(\n",
              "    \"second\",\n",
              "    comment: \"\"\n",
              ")\n"
            ]

            allow(@plugin).to receive(:run_extraction).and_return([source_result])
            allow(File).to receive(:exist?).with(source_path).and_return(true)
            allow(File).to receive(:readlines).with(source_path).and_return(source_content)

            check_strings_context(inline_mode: :source_suggestion)

            expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq([translation_suggestion_markdown])
          end

          context 'when the added string already has a translator comment' do
            let(:strings_diff) do
              <<~DIFF
                diff --git a/#{strings_path} b/#{strings_path}
                --- a/#{strings_path}
                +++ b/#{strings_path}
                @@ -1,2 +1,4 @@
                 "Existing" = "Existing";
                +/* Existing context */
                +"Add a tracking" = "Add a tracking";
              DIFF
            end

            let(:strings_content) do
              <<~STRINGS
                "Existing" = "Existing";
                /* Existing context */
                "Add a tracking" = "Add a tracking";
              STRINGS
            end

            before do
              allow(@plugin.inline_markdown_poster).to receive(:post).and_return(true)
            end

            it 'posts a replacement preview instead of skipping the string' do
              check_strings_context(inline_mode: :translation_suggestion)

              expect(@plugin.inline_markdown_poster).to have_received(:post).with(
                markdown: translation_suggestion_markdown,
                file: strings_path,
                line: 3,
                start_line: 2,
                side: 'RIGHT',
                start_side: 'RIGHT'
              )
            end
          end

          context 'when a modified string has an existing translator comment on non-added lines' do
            let(:strings_diff) do
              <<~DIFF
                diff --git a/#{strings_path} b/#{strings_path}
                --- a/#{strings_path}
                +++ b/#{strings_path}
                @@ -1,3 +1,3 @@
                 "Existing" = "Existing";
                 /* Old context */
                -"Add a tracking" = "Old value";
                +"Add a tracking" = "Add a tracking";
              DIFF
            end

            let(:strings_content) do
              <<~STRINGS
                "Existing" = "Existing";
                /* Old context */
                "Add a tracking" = "Add a tracking";
              STRINGS
            end

            it 'posts a plain text suggestion instead of a code suggestion' do
              check_strings_context(inline_mode: :translation_suggestion)

              expect_plain_text_translation_suggestion
            end

            it 'still detects long existing comments outside the previous scan cap' do
              long_comment_lines = (1..25).map { |index| "Line #{index} of translator context." }
              comment_block = [
                '/*',
                *long_comment_lines,
                '*/'
              ].join("\n")

              allow(File).to receive(:readlines).with(strings_path).and_return(
                [
                  "\"Existing\" = \"Existing\";\n",
                  *comment_block.lines,
                  "\"Add a tracking\" = \"Add a tracking\";\n"
                ]
              )

              check_strings_context(inline_mode: :translation_suggestion)

              expect_plain_text_translation_suggestion
            end
          end

          it 'falls back to plain text when inline_markdown_poster fails' do
            allow(@plugin.inline_markdown_poster).to receive(:post).and_return(false)

            check_strings_context(inline_mode: :translation_suggestion)

            expect_plain_text_translation_suggestion
          end

          it 'can include a GitHub suggestion block on the Swift source comment line' do
            source_path = 'OrderDetailViewController.swift'
            source_result = build_extraction_result(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: suggested_context,
              ui_element: 'button',
              tone: 'neutral',
              locations: ["#{source_path}:2"]
            )
            source_content = [
              "static let addTracking = NSLocalizedString(\n",
              "    \"Add a tracking\",\n",
              "    comment: \"\"\n",
              ")\n"
            ]

            allow(@plugin).to receive(:run_extraction).and_return([source_result])
            allow(File).to receive(:exist?).with(source_path).and_return(true)
            allow(File).to receive(:readlines).with(source_path).and_return(source_content)

            expected_message = <<~MESSAGE.chomp
              ```suggestion
                  comment: "#{suggested_context}"
              ```
            MESSAGE

            check_strings_context(inline_mode: :source_suggestion)

            markdown = @dangerfile.status_report[:markdowns].first
            expect(markdown).to have_attributes(
              message: expected_message,
              file: source_path,
              line: 3
            )
          end

          it 'posts inline comments by default' do
            check_strings_context

            expect(@dangerfile.status_report[:messages]).to be_empty
            expect(@dangerfile.status_report[:markdowns].length).to eq(1)
          end

          it 'posts both inline comments and summary when requested' do
            check_strings_context(summary: true)

            expect(@dangerfile.status_report[:messages]).to be_empty
            expect(@dangerfile.status_report[:markdowns].length).to eq(2)
          end

          it 'can post a plain text inline comment on the Swift source comment line' do
            source_path = 'OrderDetailViewController.swift'
            source_result = build_extraction_result(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: suggested_context,
              ui_element: 'button',
              tone: 'neutral',
              locations: ["#{source_path}:2"]
            )
            source_content = [
              "static let addTracking = NSLocalizedString(\n",
              "    \"Add a tracking\",\n",
              "    comment: \"\"\n",
              ")\n"
            ]

            allow(@plugin).to receive(:run_extraction).and_return([source_result])
            allow(File).to receive(:exist?).with(source_path).and_return(true)
            allow(File).to receive(:readlines).with(source_path).and_return(source_content)

            check_strings_context(inline_mode: :source_comment)

            markdown = @dangerfile.status_report[:markdowns].first
            expect(markdown).to have_attributes(
              message: "**Translation Context Suggestion**\n#{suggested_context}",
              file: source_path,
              line: 3
            )
          end

          it 'uses warning report type for PR-level fallback comments' do
            allow(@plugin).to receive(:resolve_inline_locations).and_return([])

            check_strings_context(report_type: :warning)

            expect(@dangerfile.status_report[:warnings].length).to eq(1)
            expect(@dangerfile.status_report[:warnings].first).to include('Translation Context Suggestion')
          end

          it 'passes provider and model through to txcontext' do
            check_strings_context(provider: :anthropic, model: 'claude-sonnet-4-6')

            expect(@plugin).to have_received(:run_extraction).with(
              hash_including(
                provider: :anthropic,
                model: 'claude-sonnet-4-6'
              )
            )
          end
        end

        context 'when an XML string has an added multi-line translator comment' do
          let(:xml_path) { 'app/src/main/res/values/strings.xml' }
          let(:xml_diff) do
            <<~DIFF
              diff --git a/#{xml_path} b/#{xml_path}
              --- a/#{xml_path}
              +++ b/#{xml_path}
              @@ -1,2 +1,6 @@
               <resources>
              +  <!--
              +    Existing context
              +  -->
              +  <string name="add_tracking">Add a tracking</string>
               </resources>
            DIFF
          end
          let(:xml_content) do
            <<~XML
              <resources>
                <!--
                  Existing context
                -->
                <string name="add_tracking">Add a tracking</string>
              </resources>
            XML
          end
          let(:mock_result) do
            build_extraction_result(
              key: 'add_tracking',
              text: 'Add a tracking',
              description: 'Button label in the order detail screen that initiates shipment tracking setup.',
              ui_element: 'button',
              tone: 'neutral'
            )
          end

          before do
            allow(@plugin).to receive_messages(load_txcontext: true, run_extraction: [mock_result])
            allow(@plugin.git).to receive(:modified_files).and_return([xml_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(xml_path)
              .and_return(GitDiffStruct.new('modified', xml_path, xml_diff))
            allow(File).to receive(:exist?).with(xml_path).and_return(true)
            allow(File).to receive(:readlines).with(xml_path).and_return(xml_content.lines)
            allow(@plugin.inline_markdown_poster).to receive(:post).and_return(true)
          end

          it 'suggests replacing the existing XML comment block in place' do
            @plugin.check_context_suggestions(
              translations: xml_path,
              source_paths: ['app/src/main/java/'],
              inline_mode: :translation_suggestion
            )

            expect(@plugin.inline_markdown_poster).to have_received(:post).with(
              markdown: <<~MESSAGE.chomp,
                ```suggestion
                  <!-- Button label in the order detail screen that initiates shipment tracking setup. -->
                  <string name="add_tracking">Add a tracking</string>
                ```
              MESSAGE
              file: xml_path,
              line: 5,
              start_line: 2,
              side: 'RIGHT',
              start_side: 'RIGHT'
            )
          end
        end

        context 'when the same key exists in multiple translation files' do
          let(:path_a) { 'res/values/strings.xml' }
          let(:path_b) { 'res/values-es/strings.xml' }
          let(:diff_a) do
            <<~DIFF
              diff --git a/#{path_a} b/#{path_a}
              --- a/#{path_a}
              +++ b/#{path_a}
              @@ -1,2 +1,3 @@
               <resources>
              +  <string name="greeting">Hello</string>
               </resources>
            DIFF
          end
          let(:diff_b) do
            <<~DIFF
              diff --git a/#{path_b} b/#{path_b}
              --- a/#{path_b}
              +++ b/#{path_b}
              @@ -1,2 +1,3 @@
               <resources>
              +  <string name="greeting">Hola</string>
               </resources>
            DIFF
          end
          let(:content_a) { ["<resources>\n", "  <string name=\"greeting\">Hello</string>\n", "</resources>\n"] }
          let(:content_b) { ["<resources>\n", "  <string name=\"greeting\">Hola</string>\n", "</resources>\n"] }
          let(:mock_result) do
            build_extraction_result(
              key: 'greeting',
              text: 'Hello',
              description: 'Greeting label on the home screen.',
              ui_element: 'label'
            )
          end

          before do
            allow(@plugin).to receive_messages(load_txcontext: true, run_extraction: [mock_result])
            allow(@plugin.git).to receive(:modified_files).and_return([path_a, path_b])
            allow(@plugin.git).to receive(:diff_for_file).with(path_a).and_return(GitDiffStruct.new('modified', path_a, diff_a))
            allow(@plugin.git).to receive(:diff_for_file).with(path_b).and_return(GitDiffStruct.new('modified', path_b, diff_b))
            allow(File).to receive(:exist?).with(path_a).and_return(true)
            allow(File).to receive(:exist?).with(path_b).and_return(true)
            allow(File).to receive(:readlines).with(path_a).and_return(content_a)
            allow(File).to receive(:readlines).with(path_b).and_return(content_b)
          end

          it 'posts inline comments on both files' do
            @plugin.check_context_suggestions(
              translations: [path_a, path_b],
              source_paths: ['app/src/main/java/']
            )

            messages = @dangerfile.status_report[:markdowns].map(&:message)
            expect(messages.length).to eq(2)
            expect(messages).to all(include('Greeting label on the home screen'))
          end
        end

        context 'when extraction returns errors' do
          let(:strings_path) { 'Localizable.strings' }
          let(:strings_diff) do
            <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -1,2 +1,3 @@
               "Existing" = "Existing";
              +"Missing Key" = "Missing";
            DIFF
          end

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, strings_diff))
          end

          it_behaves_like 'a skipped extraction result',
                          'skips results with errors',
                          {
                            key: 'Missing Key',
                            text: 'Missing',
                            description: 'Processing failed',
                            ui_element: nil,
                            tone: nil,
                            max_length: nil,
                            locations: [],
                            error: 'API error'
                          }

          it_behaves_like 'a skipped extraction result',
                          'skips results with no usage found',
                          {
                            key: 'Missing Key',
                            text: 'Missing',
                            description: 'No usage found in source code',
                            ui_element: nil,
                            tone: nil,
                            max_length: nil,
                            locations: [],
                            error: nil
                          }
        end

        context 'when extraction raises an error' do
          let(:strings_path) { 'Localizable.strings' }
          let(:strings_diff) do
            <<~DIFF
              diff --git a/#{strings_path} b/#{strings_path}
              --- a/#{strings_path}
              +++ b/#{strings_path}
              @@ -1,2 +1,3 @@
               "Existing" = "Existing";
              +"New Key" = "New Value";
            DIFF
          end

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, strings_diff))
          end

          it 'reports a warning when extraction raises' do
            allow(@plugin).to receive(:run_extraction).and_raise(StandardError.new('API connection failed'))

            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['Sources/']
            )

            expect(@dangerfile).to report_warnings(['Translation context extraction failed: API connection failed'])
          end
        end

        context 'with translations parameter as string' do
          let(:strings_path) { 'Localizable.strings' }

          before do
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, "+\"Key\" = \"Value\";\n"))
          end

          it 'accepts a single string path and normalizes to array' do
            allow(@plugin).to receive(:run_extraction).and_return([])

            # Should not raise
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: 'Sources/'
            )

            expect_no_danger_output
          end
        end
      end

      describe '#run_extraction' do
        it 'builds the txcontext config with escaped changed keys and returns extractor results' do
          stub_const('Txcontext', Module.new)
          stub_const('Txcontext::Config', Class.new)
          stub_const('Txcontext::ContextExtractor', Class.new)

          changed_keys = Set.new(['save.button', 'cart+cta'])
          config = instance_double(Txcontext::Config)
          extractor = instance_double(Txcontext::ContextExtractor)

          allow(Txcontext::Config).to receive(:new).and_return(config)
          allow(Txcontext::ContextExtractor).to receive(:new).and_return(extractor)
          allow(extractor).to receive(:run)
          allow(extractor).to receive(:results).and_return([:result])

          results = @plugin.send(
            :run_extraction,
            translations: ['Localizable.strings'],
            source_paths: ['Sources/'],
            changed_keys: changed_keys,
            provider: :anthropic,
            model: 'claude-sonnet-4-6'
          )

          expect(Txcontext::Config).to have_received(:new).with(
            translations: ['Localizable.strings'],
            source_paths: ['Sources/'],
            key_filter: 'save\.button,cart\+cta',
            provider: :anthropic,
            model: 'claude-sonnet-4-6',
            no_cache: true
          )
          expect(results).to eq([:result])
        end
      end

      describe '#load_txcontext' do
        it 'returns true when txcontext can be required' do
          allow(@plugin).to receive(:require).with('txcontext').and_return(true)

          expect(@plugin.send(:load_txcontext)).to be true
        end

        it 'returns false when requiring txcontext raises LoadError' do
          allow(@plugin).to receive(:require).with('txcontext').and_raise(LoadError)

          expect(@plugin.send(:load_txcontext)).to be false
        end
      end

      describe '#build_key_line_map' do
        it_behaves_like 'a key line map example',
                        path: 'Localizable.strings',
                        content: [
                          "/* Comment */\n",
                          "\"first_key\" = \"First\";\n",
                          "\n",
                          "\"second_key\" = \"Second\";\n"
                        ],
                        expected_locations: {
                          'first_key' => [{ file: 'Localizable.strings', line: 2, content: '"first_key" = "First";' }],
                          'second_key' => [{ file: 'Localizable.strings', line: 4, content: '"second_key" = "Second";' }]
                        }

        it_behaves_like 'a key line map example',
                        path: 'strings.xml',
                        content: [
                          "<resources>\n",
                          "  <string name=\"app_name\">My App</string>\n",
                          "  <string name=\"greeting\">Hello</string>\n",
                          "</resources>\n"
                        ],
                        expected_locations: {
                          'app_name' => [{ file: 'strings.xml', line: 2, content: '  <string name="app_name">My App</string>' }],
                          'greeting' => [{ file: 'strings.xml', line: 3, content: '  <string name="greeting">Hello</string>' }]
                        }

        it_behaves_like 'a key line map example',
                        path: 'strings.xml',
                        content: [
                          "<resources>\n",
                          "  <string-array name=\"sort_options\">\n",
                          "    <item>Name</item>\n",
                          "  </string-array>\n",
                          "  <plurals name=\"item_count\">\n",
                          "    <item quantity=\"one\">%d item</item>\n",
                          "  </plurals>\n",
                          "</resources>\n"
                        ],
                        expected_locations: {
                          'sort_options' => [{ file: 'strings.xml', line: 2, content: '  <string-array name="sort_options">' }],
                          'item_count' => [{ file: 'strings.xml', line: 5, content: '  <plurals name="item_count">' }]
                        }

        it_behaves_like 'a key line map example',
                        path: 'strings.xml',
                        content: [
                          "<resources>\n",
                          "  <string formatted=\"false\" name=\"app_name\">My App</string>\n",
                          "  <plurals translatable=\"false\" name=\"item_count\">\n",
                          "  </plurals>\n",
                          "</resources>\n"
                        ],
                        expected_locations: {
                          'app_name' => [{ file: 'strings.xml', line: 2, content: '  <string formatted="false" name="app_name">My App</string>' }],
                          'item_count' => [{ file: 'strings.xml', line: 3, content: '  <plurals translatable="false" name="item_count">' }]
                        }

        it 'collects locations from multiple files for the same key' do
          path_a = 'res/values/strings.xml'
          path_b = 'res/values-es/strings.xml'

          content_a = [
            "<resources>\n",
            "  <string name=\"greeting\">Hello</string>\n",
            "</resources>\n"
          ]
          content_b = [
            "<resources>\n",
            "  <string name=\"greeting\">Hola</string>\n",
            "</resources>\n"
          ]

          allow(File).to receive(:exist?).with(path_a).and_return(true)
          allow(File).to receive(:exist?).with(path_b).and_return(true)
          allow(File).to receive(:readlines).with(path_a).and_return(content_a)
          allow(File).to receive(:readlines).with(path_b).and_return(content_b)

          result = @plugin.send(:build_key_line_map, [path_a, path_b])

          expect(result['greeting']).to contain_exactly(
            { file: path_a, line: 2, content: '  <string name="greeting">Hello</string>' },
            { file: path_b, line: 2, content: '  <string name="greeting">Hola</string>' }
          )
        end
      end

      describe '#build_added_line_map' do
        it 'tracks added line numbers in a diff hunk' do
          path = 'Localizable.strings'
          diff = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -1,2 +1,4 @@
             "Existing" = "Existing";
            +/* Existing context */
            +"new_key" = "New Value";
          DIFF

          allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(GitDiffStruct.new('modified', path, diff))

          expect(@plugin.send(:build_added_line_map, [path])[path]).to eq(Set.new([2, 3]))
        end

        it 'handles multiple hunks' do
          path = 'Localizable.strings'
          diff = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -1,2 +1,3 @@
             "first" = "First";
            +"second" = "Second";
             "third" = "Third";
            @@ -10,2 +11,3 @@
             "tenth" = "Tenth";
            +"eleventh" = "Eleventh";
             "twelfth" = "Twelfth";
          DIFF

          allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(GitDiffStruct.new('modified', path, diff))

          expect(@plugin.send(:build_added_line_map, [path])[path]).to eq(Set.new([2, 12]))
        end

        it 'skips no-newline-at-end-of-file markers' do
          path = 'Localizable.strings'
          diff = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -1,2 +1,3 @@
             "first" = "First";
            +"second" = "Second";
            \\ No newline at end of file
          DIFF

          allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(GitDiffStruct.new('modified', path, diff))

          expect(@plugin.send(:build_added_line_map, [path])[path]).to eq(Set.new([2]))
        end

        it 'does not count removed lines toward line numbers' do
          path = 'Localizable.strings'
          diff = <<~DIFF
            diff --git a/#{path} b/#{path}
            --- a/#{path}
            +++ b/#{path}
            @@ -1,3 +1,3 @@
             "first" = "First";
            -"old" = "Old";
            +"new" = "New";
             "third" = "Third";
          DIFF

          allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(GitDiffStruct.new('modified', path, diff))

          expect(@plugin.send(:build_added_line_map, [path])[path]).to eq(Set.new([2]))
        end
      end

      describe '#format_inline_message' do
        it 'formats a result with max length metadata only' do
          result = build_extraction_result(
            description: 'Button to save user profile changes.',
            ui_element: 'button',
            tone: 'neutral',
            max_length: 20
          )

          expect(@plugin.send(:format_inline_message, result)).to eq(<<~MESSAGE.chomp)
            **Translation Context Suggestion**
            Button to save user profile changes.
            *Max length: 20*
          MESSAGE
        end

        it 'omits metadata line when no metadata present' do
          result = build_extraction_result(
            description: 'A label.',
            ui_element: nil,
            tone: nil,
            max_length: nil
          )

          expect(@plugin.send(:format_inline_message, result)).to eq(<<~MESSAGE.chomp)
            **Translation Context Suggestion**
            A label.
          MESSAGE
        end
      end

      describe '#format_inline_suggestion' do
        it 'formats a .strings suggestion as a translator comment' do
          result = build_extraction_result(description: 'Button label for saving changes.', max_length: 20)
          location = {
            file: 'Localizable.strings',
            line: 2,
            content: '    "save" = "Save";'
          }

          allow(File).to receive(:exist?).with(location[:file]).and_return(true)
          allow(File).to receive(:readlines).with(location[:file]).and_return(["\"existing\" = \"Existing\";\n", "    \"save\" = \"Save\";\n"])

          suggestion = @plugin.send(:format_inline_suggestion, result, location)

          expect(suggestion).to eq(<<~SUGGESTION.chomp)
            ```suggestion
                /* Button label for saving changes. Max length: 20. */
                "save" = "Save";
            ```
          SUGGESTION
        end

        it 'formats a Swift suggestion by replacing the comment argument' do
          result = build_extraction_result(description: 'Button label for saving changes.', max_length: 20)
          location = {
            file: 'OrderDetailViewController.swift',
            line: 3,
            content: '    comment: ""',
            inline_target: :source
          }

          suggestion = @plugin.send(:format_inline_suggestion, result, location)

          expect(suggestion).to eq(<<~SUGGESTION.chomp)
            ```suggestion
                comment: "Button label for saving changes. Max length: 20."
            ```
          SUGGESTION
        end

        it 'formats an XML suggestion as a translator comment' do
          result = build_extraction_result(description: 'Status label shown while the order is processing.')
          location = {
            file: 'strings.xml',
            line: 2,
            content: '  <string name="processing">Processing</string>'
          }

          allow(File).to receive(:exist?).with(location[:file]).and_return(true)
          allow(File).to receive(:readlines).with(location[:file]).and_return(["<resources>\n", "  <string name=\"processing\">Processing</string>\n"])

          suggestion = @plugin.send(:format_inline_suggestion, result, location)

          expect(suggestion).to eq(<<~SUGGESTION.chomp)
            ```suggestion
              <!-- Status label shown while the order is processing. -->
              <string name="processing">Processing</string>
            ```
          SUGGESTION
        end

        it 'formats the same suggestion body when a translator comment already exists' do
          result = build_extraction_result(description: 'Status label shown while the order is processing.')
          location = {
            file: 'strings.xml',
            line: 3,
            start_line: 2,
            content: '  <string name="processing">Processing</string>'
          }

          expect(@plugin.send(:format_inline_suggestion, result, location)).to eq(<<~SUGGESTION.chomp)
            ```suggestion
              <!-- Status label shown while the order is processing. -->
              <string name="processing">Processing</string>
            ```
          SUGGESTION
        end

        it 'returns nil when an existing comment is present but not in added lines' do
          result = build_extraction_result(description: 'Status label shown while processing.')
          location = {
            file: 'strings.xml',
            line: 3,
            content: '  <string name="processing">Processing</string>',
            existing_comment: true
          }

          expect(@plugin.send(:format_inline_suggestion, result, location)).to be_nil
        end
      end

      describe '#format_inline_message with inline suggestions' do
        it 'returns nil when inline suggestions are enabled but a suggestion cannot be generated' do
          result = build_extraction_result(description: 'Screen title shown at the top of the settings screen.')
          location = {
            file: 'settings.txt',
            line: 1,
            content: 'Settings'
          }

          message = @plugin.send(:format_inline_message, result, location: location, inline_suggestions: true)

          expect(message).to be_nil
        end
      end

      describe '#post_summary_table' do
        it 'sorts rows, escapes table cells, truncates long text, and includes max length' do
          results = [
            build_extraction_result(
              key: 'b|key',
              text: 'x' * 55,
              description: "Line one |\nline two",
              max_length: 20
            ),
            build_extraction_result(
              key: 'a_key',
              text: 'Short',
              description: 'First row'
            )
          ]

          @plugin.send(:post_summary_table, results)

          expect(@dangerfile.status_report[:markdowns].first.message).to eq(<<~MARKDOWN)
            ### Translation Context Suggestions

            | Key | Text | Suggested Context |
            |-----|------|-------------------|
            | `a_key` | Short | First row |
            | `b\\|key` | #{'x' * 47}... | Line one \\| line two (Max length: 20) |
          MARKDOWN
        end
      end

      describe '#build_source_line_locations' do
        it 'maps source matches to the Swift comment line' do
          result = build_extraction_result(
            description: 'Button label for saving changes.',
            locations: ['OrderDetailViewController.swift:2']
          )
          source_content = [
            "static let save = NSLocalizedString(\n",
            "    \"save\",\n",
            "    comment: \"\"\n",
            ")\n"
          ]

          allow(File).to receive(:exist?).with('OrderDetailViewController.swift').and_return(true)
          allow(File).to receive(:readlines).with('OrderDetailViewController.swift').and_return(source_content)

          expect(@plugin.send(:build_source_line_locations, result)).to eq(
            [
              {
                file: 'OrderDetailViewController.swift',
                line: 3,
                content: '    comment: ""',
                inline_target: :source
              }
            ]
          )
        end
      end

      describe '#skip_result?' do
        it 'skips results with errors' do
          result = build_extraction_result(error: 'API error', description: 'some desc')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with no usage found' do
          result = build_extraction_result(error: nil, description: 'No usage found in source code')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with processing failed' do
          result = build_extraction_result(error: nil, description: 'Processing failed')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'does not skip valid results' do
          result = build_extraction_result(error: nil, description: 'Button label for saving.')
          expect(@plugin.send(:skip_result?, result)).to be false
        end
      end
    end
  end
end
