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
            double(
              'ExtractionResult',
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
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file)
              .with(strings_path)
              .and_return(GitDiffStruct.new('modified', strings_path, strings_diff))
            allow(@plugin).to receive(:run_extraction).and_return([mock_result])
            allow(File).to receive(:exist?).with(strings_path).and_return(true)
            allow(File).to receive(:readlines).with(strings_path).and_return(strings_content.lines)
          end

          it 'posts inline message with context suggestion' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              summary: false
            )

            messages = @dangerfile.status_report[:messages]
            expect(messages.length).to eq(1)
            expect(messages.first).to include('Translation Context Suggestion')
            expect(messages.first).to include('Button label in the order detail screen')
            expect(messages.first).to include('UI: button')
          end

          it 'posts a summary markdown table' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              inline: false,
              summary: true
            )

            markdowns = @dangerfile.status_report[:markdowns]
            expect(markdowns.length).to eq(1)

            table_text = markdowns.first.message
            expect(table_text).to include('Translation Context Suggestions')
            expect(table_text).to include('Add a tracking')
            expect(table_text).to include('Button label in the order detail screen')
            expect(table_text).to include('button')
          end

          it 'posts both inline and summary by default' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/']
            )

            expect(@dangerfile.status_report[:messages].length).to eq(1)
            expect(@dangerfile.status_report[:markdowns].length).to eq(1)
          end

          it 'uses warning report type when specified' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              report_type: :warning,
              summary: false
            )

            expect(@dangerfile.status_report[:warnings].length).to eq(1)
            expect(@dangerfile.status_report[:warnings].first).to include('Translation Context Suggestion')
          end

          it 'passes provider and model through to txcontext' do
            @plugin.check_context_suggestions(
              translations: strings_path,
              source_paths: ['WooCommerce/'],
              provider: :anthropic,
              model: 'claude-sonnet-4-6',
              summary: false
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
            double(
              'ExtractionResult',
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
            allow(@plugin).to receive(:load_txcontext).and_return(true)
            allow(@plugin.git).to receive(:modified_files).and_return([path_a, path_b])
            allow(@plugin.git).to receive(:diff_for_file).with(path_a).and_return(GitDiffStruct.new('modified', path_a, diff_a))
            allow(@plugin.git).to receive(:diff_for_file).with(path_b).and_return(GitDiffStruct.new('modified', path_b, diff_b))
            allow(@plugin).to receive(:run_extraction).and_return([mock_result])
            allow(File).to receive(:exist?).with(path_a).and_return(true)
            allow(File).to receive(:exist?).with(path_b).and_return(true)
            allow(File).to receive(:readlines).with(path_a).and_return(content_a)
            allow(File).to receive(:readlines).with(path_b).and_return(content_b)
          end

          it 'posts inline comments on both files' do
            @plugin.check_context_suggestions(
              translations: [path_a, path_b],
              source_paths: ['app/src/main/java/'],
              summary: false
            )

            messages = @dangerfile.status_report[:messages]
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
            error_result = double(
              'ExtractionResult',
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
            no_usage_result = double(
              'ExtractionResult',
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

          expect(result['first_key']).to eq([{ file: path, line: 2 }])
          expect(result['second_key']).to eq([{ file: path, line: 4 }])
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

          expect(result['app_name']).to eq([{ file: path, line: 2 }])
          expect(result['greeting']).to eq([{ file: path, line: 3 }])
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

          expect(result['sort_options']).to eq([{ file: path, line: 2 }])
          expect(result['item_count']).to eq([{ file: path, line: 5 }])
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

          expect(result['app_name']).to eq([{ file: path, line: 2 }])
          expect(result['item_count']).to eq([{ file: path, line: 3 }])
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
            { file: path_a, line: 2 },
            { file: path_b, line: 2 }
          )
        end
      end

      describe '#format_inline_message' do
        it 'formats a result with all metadata' do
          result = double(
            'ExtractionResult',
            description: 'Button to save user profile changes.',
            ui_element: 'button',
            tone: 'neutral',
            max_length: 20
          )

          message = @plugin.send(:format_inline_message, result)

          expect(message).to include('Translation Context Suggestion')
          expect(message).to include('Button to save user profile changes.')
          expect(message).to include('UI: button')
          expect(message).to include('Tone: neutral')
          expect(message).to include('Max length: 20')
        end

        it 'omits metadata line when no metadata present' do
          result = double(
            'ExtractionResult',
            description: 'A label.',
            ui_element: nil,
            tone: nil,
            max_length: nil
          )

          message = @plugin.send(:format_inline_message, result)

          expect(message).to include('A label.')
          expect(message).not_to include('UI:')
          expect(message).not_to include('Tone:')
        end
      end

      describe '#skip_result?' do
        it 'skips results with errors' do
          result = double('ExtractionResult', error: 'API error', description: 'some desc')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with no usage found' do
          result = double('ExtractionResult', error: nil, description: 'No usage found in source code')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'skips results with processing failed' do
          result = double('ExtractionResult', error: nil, description: 'Processing failed')
          expect(@plugin.send(:skip_result?, result)).to be true
        end

        it 'does not skip valid results' do
          result = double('ExtractionResult', error: nil, description: 'Button label for saving.')
          expect(@plugin.send(:skip_result?, result)).to be false
        end
      end
    end
  end
end
