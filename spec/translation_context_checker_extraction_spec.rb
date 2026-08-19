# frozen_string_literal: true

require_relative 'spec_helper'
require_relative 'support/translation_context_checker_context'

module Danger
  describe Danger::TranslationContextChecker do
    describe 'with Dangerfile' do
      include_context 'with translation context checker'

      describe '#run_extraction' do
        it 'passes the explicit Danger diff range and normalized API values to the extractor' do
          config = instance_double(I18nContextGenerator::Config)
          extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, results: [:result])

          allow(Danger::EnvironmentManager).to receive_messages(
            danger_base_branch: 'danger_base',
            danger_head_branch: 'danger_head'
          )
          allow(I18nContextGenerator::Config).to receive(:new).and_return(config)
          allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(
            config,
            quiet: true,
            progress: false
          ).and_return(extractor)

          results = @plugin.send(
            :run_extraction,
            translation_paths: ['Localizable.strings'],
            source_paths: ['Sources'],
            discovery_mode: :translations,
            provider: :openai,
            model: 'gpt-5-mini',
            context_files: ['GLOSSARY.md'],
            supplemental_context: {
              'Pull request title' => 'Improve settings'
            }
          )

          expect(I18nContextGenerator::Config).to have_received(:new).with(
            translations: ['Localizable.strings'],
            source_paths: ['Sources'],
            discovery_mode: :translations,
            provider: :openai,
            model: 'gpt-5-mini',
            context_files: ['GLOSSARY.md'],
            supplemental_context: {
              'Pull request title' => 'Improve settings'
            },
            no_cache: true,
            diff_base: 'danger_base',
            diff_head: 'danger_head'
          )
          expect(results).to eq([:result])
        end
      end
    end
  end
end
