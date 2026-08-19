# frozen_string_literal: true

require_relative 'spec_helper'
require_relative 'support/translation_context_checker_context'

module Danger
  describe Danger::TranslationContextChecker do
    describe 'with Dangerfile' do
      include_context 'with translation context checker'

      describe 'publishing results' do
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
            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path
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
            expect(@plugin.git).not_to have_received(:diff_for_file)
          end

          it 'builds an apply-ready translation suggestion' do
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path, 'Sources/View.swift'])

            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
              inline_mode: :translation_suggestion
            )

            expect(status_markdowns.fetch(0).message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
              /* Button that saves the edited settings. Max length: 20. */
              "save.button" = "Save";
              ```
            MARKDOWN
            expect(@plugin.git).to have_received(:diff_for_file).once.with(strings_path)
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

            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: [strings_path, second_path]
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

            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
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
            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
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

            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
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

        context 'when only a one-line translator comment changed' do
          let(:strings_path) { 'Localizable.strings' }
          let(:content) do
            [
              "/* Better context */\n",
              "\"save.button\" = \"Save\";\n"
            ]
          end
          let(:result) do
            build_extraction_result(
              key: 'save.button',
              description: 'Button that saves the edited settings.',
              changed_translation_locations: ["#{strings_path}:1"]
            )
          end

          before do
            allow(@plugin.git).to receive(:modified_files).and_return([strings_path])
            allow(@plugin.git).to receive(:diff_for_file).with(strings_path).and_return(
              GitDiffStruct.new(
                'modified',
                strings_path,
                <<~DIFF
                  diff --git a/#{strings_path} b/#{strings_path}
                  --- a/#{strings_path}
                  +++ b/#{strings_path}
                  @@ -1,2 +1,2 @@
                  -/* Old context */
                  +/* Better context */
                   "save.button" = "Save";
                DIFF
              )
            )
            allow(File).to receive(:exist?).with(strings_path).and_return(true)
            allow(File).to receive(:readlines).with(strings_path).and_return(content)
            allow(@plugin).to receive(:run_extraction).and_return([result])
          end

          it 'posts feedback on the exact changed comment line' do
            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.file, markdown.line]).to eq([strings_path, 1])
          end

          it 'replaces the changed comment instead of nesting another comment' do
            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
              inline_mode: :translation_suggestion
            )

            markdown = status_markdowns.fetch(0)
            expect([markdown.message, markdown.line, markdown.start_line]).to eq(
              [
                <<~MARKDOWN.chomp,
                  ```suggestion
                  /* Button that saves the edited settings. */
                  ```
                MARKDOWN
                1,
                nil
              ]
            )
          end
        end

        context 'when the changed entry carries a same-line translator comment' do
          let(:description) { 'Button that saves the edited settings.' }

          def stub_single_line_entry(path, entry)
            allow(@plugin.git).to receive(:modified_files).and_return([path])
            allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(
              GitDiffStruct.new('modified', path, added_file_diff(path, [entry]))
            )
            allow(File).to receive(:exist?).with(path).and_return(true)
            allow(File).to receive(:readlines).with(path).and_return([entry])
            allow(@plugin).to receive(:run_extraction).and_return(
              [
                build_extraction_result(
                  key: 'save.button',
                  description: description,
                  changed_translation_locations: ["#{path}:1"]
                )
              ]
            )
          end

          it 'keeps the .strings entry in the apply-ready suggestion' do
            strings_path = 'Localizable.strings'
            stub_single_line_entry(strings_path, %("save.button" = "Save"; /* Old context */\n))

            @plugin.check_resource_changes(
              source_paths: 'Sources',
              resource_paths: strings_path,
              inline_mode: :translation_suggestion
            )

            expect(status_markdowns.fetch(0).message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
              /* Button that saves the edited settings. */
              "save.button" = "Save";
              ```
            MARKDOWN
          end

          it 'keeps the strings.xml entry in the apply-ready suggestion' do
            xml_path = 'app/src/main/res/values/strings.xml'
            stub_single_line_entry(xml_path, %(  <string name="save">Save</string> <!-- Old context -->\n))

            @plugin.check_resource_changes(
              source_paths: 'app/src/main/java',
              resource_paths: xml_path,
              inline_mode: :translation_suggestion
            )

            expect(status_markdowns.fetch(0).message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
                <!-- Button that saves the edited settings. -->
                <string name="save">Save</string>
              ```
            MARKDOWN
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
            @plugin.check_resource_changes(
              source_paths: 'app/src/main/java',
              resource_paths: xml_path
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
              locations: ["#{source_path}:2", "#{source_path}:3", 'Sources/Other.swift:8'],
              changed_locations: ["#{source_path}:2", "#{source_path}:3"],
              changed_location_groups: [["#{source_path}:2", "#{source_path}:3"]]
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
            @plugin.check_source_changes(
              source_paths: 'Sources',
              inline_mode: :source_comment
            )

            markdown = status_markdowns.fetch(0)
            expect(
              [status_markdowns.size, markdown.file, markdown.line,
               markdown.message.include?('Title for the settings screen.')]
            ).to eq(
              [1, source_path, 3, true]
            )
            expect(@plugin.git).not_to have_received(:diff_for_file)
          end

          it 'offers a Swift comment suggestion on an added comment line' do
            @plugin.check_source_changes(
              source_paths: 'Sources',
              inline_mode: :source_suggestion
            )

            markdown = status_markdowns.fetch(0)
            expect([status_markdowns.size, markdown.file, markdown.line]).to eq([1, source_path, 3])
            expect(markdown.message).to eq(<<~MARKDOWN.chomp)
              ```suggestion
                                   comment: "Title for the settings screen.")
              ```
            MARKDOWN
          end

          it 'falls back to PR-level feedback when suggestion line lookup fails' do
            git_diff = instance_double(I18nContextGenerator::GitDiff)
            allow(git_diff).to receive(:changed_lines).and_raise(
              I18nContextGenerator::Error,
              'Git diff failed for danger_base...danger_head'
            )
            allow(I18nContextGenerator::GitDiff).to receive(:new).and_return(git_diff)

            @plugin.check_source_changes(
              source_paths: 'Sources',
              inline_mode: :source_suggestion
            )

            expect(@dangerfile.status_report[:warnings]).to eq(
              ['Translation context suggestion line lookup failed: Git diff failed for danger_base...danger_head']
            )
            expect(@dangerfile.status_report[:messages]).to eq(
              ["**Translation Context Suggestion**\nTitle for the settings screen."]
            )
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
            allow(@plugin).to receive(:run_extraction).and_return(
              [
                build_extraction_result(
                  key: 'settings.title',
                  description: 'Title for the settings screen.',
                  locations: ["#{source_path}:2", "#{source_path}:3"],
                  changed_locations: ["#{source_path}:2"],
                  changed_location_groups: [["#{source_path}:2"]]
                )
              ]
            )

            @plugin.check_source_changes(
              source_paths: 'Sources',
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
            build_extraction_result(
              key: 'z|key',
              source_file: 'Resources/Z.strings',
              text: "First\nline",
              description: 'Z description'
            ),
            build_extraction_result(
              key: 'a.key',
              source_file: 'Resources/A.strings',
              text: 'A',
              description: 'A|description'
            )
          ]
          allow(@plugin.git).to receive(:modified_files).and_return(['Sources/MyView.swift'])
          allow(@plugin).to receive(:run_extraction).and_return(results)

          @plugin.check_source_changes(
            source_paths: 'Sources',
            inline_mode: :none,
            summary: true
          )

          table = status_markdowns.fetch(0).message
          expect(
            [
              table.index('`a.key`') < table.index('`z\\|key`'),
              table.include?('A\\|description'),
              table.include?('First line'),
              table.include?('Resources/A.strings')
            ]
          ).to eq([true, true, true, true])
        end
      end
    end
  end
end
