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

            expect(@dangerfile).to not_report
          end
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

          let(:mock_result) do
            ExtractionResultStruct.new(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: 'Button label in the order detail screen that initiates shipment tracking setup.',
              ui_element: 'button',
              tone: 'neutral',
              max_length: nil,
              locations: ['OrderDetailViewController.swift:42'],
              error: nil
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

          it 'posts inline message with context suggestion' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/']
            )

            expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq(
              ['**Translation Context Suggestion**' \
               "\nButton label in the order detail screen that initiates shipment tracking setup."]
            )
          end

          it 'posts a summary markdown table' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              report_location: :summary
            )

            expect(@dangerfile.status_report[:markdowns].first.message).to eq(<<~MARKDOWN)
              ### Translation Context Suggestions

              | Key | Text | Suggested Context |
              |-----|------|-------------------|
              | `Add a tracking` | Add a tracking | Button label in the order detail screen that initiates shipment tracking setup. |
            MARKDOWN
          end

          it 'can include a GitHub suggestion block in inline comments' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              inline_suggestions: true
            )

            expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq([<<~MESSAGE.chomp])
              ```suggestion
              /* Button label in the order detail screen that initiates shipment tracking setup. */
              "Add a tracking" = "Add a tracking";
              ```
            MESSAGE
          end

          context 'when the added string already has a translator comment' do
            let(:github_api) { instance_double(Octokit::Client) }
            let(:github_plugin) do
              instance_double(
                Danger::DangerfileGitHubPlugin,
                pr_json: {
                  'base' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } },
                  'number' => 42,
                  'head' => { 'sha' => 'abc123' }
                },
                api: github_api
              )
            end
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
              allow(@plugin).to receive(:github).and_return(github_plugin)
              allow(github_api).to receive_messages(
                pull_request_comments: [],
                create_pull_request_comment: {
                  'id' => 123,
                  'body' => '',
                  'path' => strings_path,
                  'line' => 3,
                  'start_line' => 2
                }
              )
            end

            it 'posts a replacement preview instead of skipping the string' do
              @plugin.check_context_suggestions(
                translations: strings_path,
                source_paths: ['WooCommerce/'],
                inline_suggestions: true
              )

              expect(github_api).to have_received(:create_pull_request_comment).with(
                'Automattic/dangermattic',
                42,
                <<~MESSAGE.chomp,
                  <!-- dangermattic-translation-context -->
                  ```suggestion
                  /* Button label in the order detail screen that initiates shipment tracking setup. */
                  "Add a tracking" = "Add a tracking";
                  ```
                MESSAGE
                'abc123',
                strings_path,
                3,
                start_line: 2,
                side: 'RIGHT',
                start_side: 'RIGHT'
              )
            end
          end

          it 'can include a GitHub suggestion block on the Swift source comment line' do
            source_path = 'OrderDetailViewController.swift'
            source_result = ExtractionResultStruct.new(
              key: 'Add a tracking',
              text: 'Add a tracking',
              description: 'Button label in the order detail screen that initiates shipment tracking setup.',
              ui_element: 'button',
              tone: 'neutral',
              max_length: nil,
              locations: ["#{source_path}:2"],
              error: nil
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
            allow(@plugin).to receive(:markdown)

            expected_message = <<~MESSAGE.chomp
              ```suggestion
                  comment: "Button label in the order detail screen that initiates shipment tracking setup."
              ```
            MESSAGE

            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              inline_suggestions: true,
              inline_suggestion_target: :source
            )

            expect(@plugin).to have_received(:markdown).with(
              expected_message,
              file: source_path,
              line: 3
            )
          end

          it 'posts inline comments by default' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/']
            )

            expect(@dangerfile.status_report[:messages]).to be_empty
            expect(@dangerfile.status_report[:markdowns].length).to eq(1)
          end

          it 'posts both inline comments and summary when requested' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              report_location: :both
            )

            expect(@dangerfile.status_report[:messages]).to be_empty
            expect(@dangerfile.status_report[:markdowns].length).to eq(2)
          end

          it 'supports the legacy inline and summary flags' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              inline: false,
              summary: true
            )

            expect(@dangerfile.status_report[:messages]).to be_empty
            expect(@dangerfile.status_report[:markdowns].length).to eq(1)
          end

          it 'uses warning report type for PR-level fallback comments' do
            allow(@plugin).to receive(:resolve_inline_locations).and_return([])

            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              report_type: :warning
            )

            expect(@dangerfile.status_report[:warnings].length).to eq(1)
            expect(@dangerfile.status_report[:warnings].first).to include('Translation Context Suggestion')
          end

          it 'passes provider and model through to txcontext' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              provider: :anthropic,
              model: 'claude-sonnet-4-6'
            )

            expect(@plugin).to have_received(:run_extraction).with(
              hash_including(
                provider: :anthropic,
                model: 'claude-sonnet-4-6'
              )
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
            ExtractionResultStruct.new(
              key: 'greeting',
              text: 'Hello',
              description: 'Greeting label on the home screen.',
              ui_element: 'label',
              tone: nil,
              max_length: nil,
              locations: [],
              error: nil
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

          it 'skips results with errors' do
            error_result = ExtractionResultStruct.new(
              key: 'Missing Key',
              text: 'Missing',
              description: 'Processing failed',
              ui_element: nil,
              tone: nil,
              max_length: nil,
              locations: [],
              error: 'API error'
            )
            allow(@plugin).to receive(:run_extraction).and_return([error_result])

            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['Sources/']
            )

            expect(@dangerfile).to not_report
          end

          it 'skips results with no usage found' do
            no_usage_result = ExtractionResultStruct.new(
              key: 'Missing Key',
              text: 'Missing',
              description: 'No usage found in source code',
              ui_element: nil,
              tone: nil,
              max_length: nil,
              locations: [],
              error: nil
            )
            allow(@plugin).to receive(:run_extraction).and_return([no_usage_result])

            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['Sources/']
            )

            expect(@dangerfile).to not_report
          end
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

            expect(@dangerfile).to not_report
          end
        end
      end

      describe '#build_key_line_map' do
        it 'maps .strings keys to their line numbers' do
          path = 'Localizable.strings'
          content = [
            "/* Comment */\n",
            "\"first_key\" = \"First\";\n",
            "\n",
            "\"second_key\" = \"Second\";\n"
          ]

          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:readlines).with(path).and_return(content)

          result = @plugin.send(:build_key_line_map, [path])

          expect(result['first_key']).to eq([{ file: path, line: 2, content: '"first_key" = "First";' }])
          expect(result['second_key']).to eq([{ file: path, line: 4, content: '"second_key" = "Second";' }])
        end

        it 'maps strings.xml <string> keys to their line numbers' do
          path = 'strings.xml'
          content = [
            "<resources>\n",
            "  <string name=\"app_name\">My App</string>\n",
            "  <string name=\"greeting\">Hello</string>\n",
            "</resources>\n"
          ]

          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:readlines).with(path).and_return(content)

          result = @plugin.send(:build_key_line_map, [path])

          expect(result['app_name']).to eq([{ file: path, line: 2, content: '  <string name="app_name">My App</string>' }])
          expect(result['greeting']).to eq([{ file: path, line: 3, content: '  <string name="greeting">Hello</string>' }])
        end

        it 'maps strings.xml <string-array> and <plurals> keys to their line numbers' do
          path = 'strings.xml'
          content = [
            "<resources>\n",
            "  <string-array name=\"sort_options\">\n",
            "    <item>Name</item>\n",
            "  </string-array>\n",
            "  <plurals name=\"item_count\">\n",
            "    <item quantity=\"one\">%d item</item>\n",
            "  </plurals>\n",
            "</resources>\n"
          ]

          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:readlines).with(path).and_return(content)

          result = @plugin.send(:build_key_line_map, [path])

          expect(result['sort_options']).to eq([{ file: path, line: 2, content: '  <string-array name="sort_options">' }])
          expect(result['item_count']).to eq([{ file: path, line: 5, content: '  <plurals name="item_count">' }])
        end

        it 'matches XML tags with reordered attributes' do
          path = 'strings.xml'
          content = [
            "<resources>\n",
            "  <string formatted=\"false\" name=\"app_name\">My App</string>\n",
            "  <plurals translatable=\"false\" name=\"item_count\">\n",
            "  </plurals>\n",
            "</resources>\n"
          ]

          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:readlines).with(path).and_return(content)

          result = @plugin.send(:build_key_line_map, [path])

          expect(result['app_name']).to eq([{ file: path, line: 2, content: '  <string formatted="false" name="app_name">My App</string>' }])
          expect(result['item_count']).to eq([{ file: path, line: 3, content: '  <plurals translatable="false" name="item_count">' }])
        end

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
      end

      describe '#format_inline_message' do
        it 'formats a result with max length metadata only' do
          result = ExtractionResultStruct.new(
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
          result = ExtractionResultStruct.new(
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
          result = ExtractionResultStruct.new(description: 'Button label for saving changes.', max_length: 20)
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
          result = ExtractionResultStruct.new(description: 'Button label for saving changes.', max_length: 20)
          location = {
            file: 'OrderDetailViewController.swift',
            line: 3,
            content: '    comment: ""',
            suggestion_target: :source
          }

          suggestion = @plugin.send(:format_inline_suggestion, result, location)

          expect(suggestion).to eq(<<~SUGGESTION.chomp)
            ```suggestion
                comment: "Button label for saving changes. Max length: 20."
            ```
          SUGGESTION
        end

        it 'formats an XML suggestion as a translator comment' do
          result = ExtractionResultStruct.new(description: 'Status label shown while the order is processing.')
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
          result = ExtractionResultStruct.new(description: 'Status label shown while the order is processing.')
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
      end

      describe '#format_inline_message with inline suggestions' do
        it 'returns nil when inline suggestions are enabled but a suggestion cannot be generated' do
          result = ExtractionResultStruct.new(description: 'Screen title shown at the top of the settings screen.')
          location = {
            file: 'settings.txt',
            line: 1,
            content: 'Settings'
          }

          message = @plugin.send(:format_inline_message, result, location: location, inline_suggestions: true)

          expect(message).to be_nil
        end
      end

      describe '#build_source_line_locations' do
        it 'maps source matches to the Swift comment line' do
          result = ExtractionResultStruct.new(
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
                suggestion_target: :source
              }
            ]
          )
        end
      end

      describe '#skip_result?' do
        it 'skips results with errors' do
          result = ExtractionResultStruct.new(error: 'API error', description: 'some desc')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with no usage found' do
          result = ExtractionResultStruct.new(error: nil, description: 'No usage found in source code')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with processing failed' do
          result = ExtractionResultStruct.new(error: nil, description: 'Processing failed')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'does not skip valid results' do
          result = ExtractionResultStruct.new(error: nil, description: 'Button label for saving.')
          expect(@plugin.send(:skip_result?, result)).to be false
        end
      end
    end
  end
end
