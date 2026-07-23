# frozen_string_literal: true

module Danger
  # Extractor adapter for TranslationContextChecker.
  module TranslationContextCheckerExtraction
    private

    def run_extraction(translation_paths:, source_paths:, provider:, model:, discovery_mode:)
      diff_base, diff_head = danger_diff_range
      config = I18nContextGenerator::Config.new(
        translations: translation_paths,
        source_paths: source_paths,
        discovery_mode: discovery_mode,
        provider: provider,
        model: model,
        no_cache: true,
        diff_base: diff_base,
        diff_head: diff_head
      )

      extractor = I18nContextGenerator::ContextExtractor.new(
        config,
        quiet: true,
        progress: false
      )
      extractor.run
      extractor.results
    end

    def danger_diff_range
      [
        Danger::EnvironmentManager.danger_base_branch,
        Danger::EnvironmentManager.danger_head_branch
      ]
    end
  end
end
