# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

module Danger
  describe Danger::TranslationContextChecker, 'extractor integration' do
    before do
      @dangerfile = testing_dangerfile
      @plugin = @dangerfile.translation_context_checker
      @llm = instance_double(I18nContextGenerator::LLM::Client)

      allow(@llm).to receive(:generate_context) do |key:, **|
        I18nContextGenerator::LLM::ContextResult.new(description: "Context for #{key}")
      end
      allow(I18nContextGenerator::LLM::Client).to receive(:for).and_return(@llm)
    end

    def write_fixture(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def run_git(*arguments)
      output, error, status = Open3.capture3('git', *arguments)
      raise "git #{arguments.join(' ')} failed: #{error}" unless status.success?

      output.strip
    end

    def commit_fixture(message)
      run_git('add', '.')
      run_git('commit', '-m', message)
      run_git('rev-parse', 'HEAD')
    end

    def with_fixture_repo
      Dir.mktmpdir('dangermattic-extractor-contract') do |directory|
        Dir.chdir(directory) do
          run_git('init', '--initial-branch=main')
          run_git('config', 'user.name', 'Dangermattic Specs')
          run_git('config', 'user.email', 'dangermattic@example.com')
          yield
        end
      end
    end

    def run_extraction(base_ref:, source_path:, translation_path: nil, discovery_mode: :translations)
      head_ref = run_git('rev-parse', 'HEAD')
      allow(Danger::EnvironmentManager).to receive_messages(
        danger_base_branch: base_ref,
        danger_head_branch: head_ref
      )

      @plugin.send(
        :run_extraction,
        translation_paths: Array(translation_path).compact,
        source_paths: [source_path],
        discovery_mode: discovery_mode,
        provider: :anthropic,
        model: nil
      )
    end

    it 'preserves punctuation and comma-containing iOS keys through the real diff contract' do
      with_fixture_repo do
        translation_path = 'Resources/Localizable.strings'
        source_path = 'Sources/Strings.swift'
        keys = ['save.button', 'cart+cta', 'key,with,commas']
        write_fixture(translation_path, "\"existing\" = \"Existing\";\n")
        write_fixture(
          source_path,
          keys.map { |key| "let value = String(localized: \"#{key}\", comment: \"\")" }.join("\n")
        )
        base_ref = commit_fixture('Base fixture')
        write_fixture(
          translation_path,
          <<~STRINGS
            "existing" = "Existing";
            "save.button" = "Save";
            "cart+cta" = "Cart";
            "key,with,commas" = "Commas";
          STRINGS
        )
        commit_fixture('Change translations')

        results = run_extraction(
          base_ref: base_ref,
          translation_path: translation_path,
          source_path: 'Sources'
        )

        expect(results.map(&:key)).to match_array(keys)
        expect(results.to_h { |result| [result.key, result.changed_translation_locations] }).to eq(
          'save.button' => ["#{translation_path}:2"],
          'cart+cta' => ["#{translation_path}:3"],
          'key,with,commas' => ["#{translation_path}:4"]
        )
      end
    end

    it 'selects an iOS entry when only its translator comment changed' do
      with_fixture_repo do
        translation_path = 'Resources/Localizable.strings'
        source_path = 'Sources/Strings.swift'
        write_fixture(
          translation_path,
          <<~STRINGS
            /* Old context */
            "save.button" = "Save";
          STRINGS
        )
        write_fixture(source_path, 'let title = String(localized: "save.button", comment: "")')
        base_ref = commit_fixture('Base fixture')
        write_fixture(
          translation_path,
          <<~STRINGS
            /* Better context */
            "save.button" = "Save";
          STRINGS
        )
        commit_fixture('Change translator comment')

        results = run_extraction(
          base_ref: base_ref,
          translation_path: translation_path,
          source_path: 'Sources'
        )

        expect([results.map(&:key), results.first.changed_translation_locations]).to eq(
          [['save.button'], ["#{translation_path}:1"]]
        )
        expect(@llm).to have_received(:generate_context).with(
          hash_including(key: 'save.button', comment: 'Better context')
        )
      end
    end

    it 'selects only the changed Android collection member and retains its exact line' do
      with_fixture_repo do
        translation_path = 'app/src/main/res/values/strings.xml'
        source_path = 'app/src/main/java/Items.kt'
        write_fixture(
          translation_path,
          <<~XML
            <resources>
              <plurals name="item_count">
                <item quantity="one">%d item</item>
                <item quantity="other">%d items</item>
              </plurals>
            </resources>
          XML
        )
        write_fixture(
          source_path,
          'val label = resources.getQuantityString(R.plurals.item_count, count, count)'
        )
        base_ref = commit_fixture('Base fixture')
        write_fixture(
          translation_path,
          <<~XML
            <resources>
              <plurals name="item_count">
                <item quantity="one">%d item</item>
                <item quantity="other">%d total items</item>
              </plurals>
            </resources>
          XML
        )
        commit_fixture('Change plural member')

        results = run_extraction(
          base_ref: base_ref,
          translation_path: translation_path,
          source_path: 'app/src/main/java'
        )

        expect(results.map(&:key)).to eq(['item_count:other'])
        expect(results.first.changed_translation_locations).to eq(["#{translation_path}:4"])
      end
    end

    it 'extracts a multiline Swift localization when only its comment line changed' do
      with_fixture_repo do
        source_file = 'Sources/SettingsView.swift'
        write_fixture(
          source_file,
          <<~SWIFT
            let title = String(localized: "settings.title",
                               comment: "Old context")
          SWIFT
        )
        base_ref = commit_fixture('Base fixture')
        write_fixture(
          source_file,
          <<~SWIFT
            let title = String(localized: "settings.title",
                               comment: "Improved context")
          SWIFT
        )
        commit_fixture('Change localization comment')

        results = run_extraction(
          base_ref: base_ref,
          source_path: 'Sources',
          discovery_mode: :source
        )

        expect(
          [
            results.map(&:key),
            results.first.locations,
            results.first.changed_locations,
            results.first.changed_location_groups
          ]
        ).to eq(
          [
            ['settings.title'],
            ["#{source_file}:1", "#{source_file}:2"],
            ["#{source_file}:2"],
            [["#{source_file}:2"]]
          ]
        )
        expect(@llm).to have_received(:generate_context).with(
          hash_including(key: 'settings.title', comment: 'Improved context')
        )
      end
    end

    it 'posts one inline result per newly added multiline source occurrence' do
      with_fixture_repo do
        source_file = 'Sources/SettingsView.swift'
        write_fixture(source_file, "struct SettingsView {}\n")
        base_ref = commit_fixture('Base fixture')
        write_fixture(
          source_file,
          <<~SWIFT
            struct SettingsView {
              let title = String(localized: "settings.title",
                                 comment: "")
            }
          SWIFT
        )
        commit_fixture('Add localization call')

        results = run_extraction(
          base_ref: base_ref,
          source_path: 'Sources',
          discovery_mode: :source
        )
        allow(@plugin).to receive(:build_added_line_map)
          .with([source_file]).and_return(source_file => Set[2, 3])

        @plugin.send(:post_inline_comments, results, :message, inline_mode: :source_comment)
        @plugin.send(:post_inline_comments, results, :message, inline_mode: :source_suggestion)

        expect([results.first.changed_locations, results.first.changed_location_groups]).to eq(
          [["#{source_file}:2", "#{source_file}:3"], [["#{source_file}:2", "#{source_file}:3"]]]
        )
        expect(
          @dangerfile.status_report[:markdowns].map do |markdown|
            [markdown.file, markdown.line, markdown.message.include?('```suggestion')]
          end
        ).to eq([[source_file, 3, false], [source_file, 3, true]])
      end
    end
  end
end
