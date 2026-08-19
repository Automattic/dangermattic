# frozen_string_literal: true

require 'pathname'
# Used directly below; keep this entry point independent of transitive requires.
require 'set' # rubocop:disable Lint/RedundantRequireStatement
require 'i18n_context_generator'
require_relative 'translation_context_checker/extraction'
require_relative 'translation_context_checker/location_resolver'
require_relative 'translation_context_checker/publisher'
require_relative 'translation_context_checker/suggestion_renderer'

module Danger
  # Suggests translator context for localization entries changed in a pull request.
  #
  # Relevant source snippets are sent to the configured external LLM provider.
  # The matching provider API key must be available in CI.
  #
  # @example Source-backed Swift suggestions
  #   translation_context_checker.check_context_suggestions(
  #     source_paths: ['Sources/'],
  #     discovery_mode: :source,
  #     inline_mode: :source_suggestion
  #   )
  #
  # @example Resource-backed Android suggestions
  #   translation_context_checker.check_context_suggestions(
  #     source_paths: ['app/src/main/java/'],
  #     discovery_mode: :translations,
  #     translation_paths: ['app/src/main/res/values/strings.xml']
  #   )
  #
  # @see Automattic/dangermattic
  # @tags localization, translation, context
  class TranslationContextChecker < Plugin
    include TranslationContextCheckerExtraction
    include TranslationContextCheckerLocationResolver
    include TranslationContextCheckerPublisher
    include TranslationContextCheckerSuggestionRenderer

    VALID_DISCOVERY_MODES = %i[auto translations source].freeze
    VALID_INLINE_MODES = %i[
      translation_comment
      translation_suggestion
      source_comment
      source_suggestion
      none
    ].freeze
    SWIFT_COMMENT_ARGUMENT_PATTERN = /comment:\s*"((?:\\.|[^"\\])*)"/

    # Analyze changed localization entries and report generated translator context.
    #
    # @param source_paths [String, Array<String>] Explicit source search scope.
    # @param discovery_mode [Symbol, String] :auto, :translations, or :source.
    # @param translation_paths [String, Array<String>, nil] Translation inputs.
    # @param context_files [String, Array<String>, nil] Free-form files included in full as untrusted evidence.
    # @param include_pull_request_context [Boolean] Include the PR title and description as untrusted evidence.
    # @param inline_mode [Symbol, String, nil] Inline comment/suggestion target.
    # @param summary [Boolean] Whether to add a PR-level summary table.
    # @param report_type [Symbol] Severity for PR-level fallback reports.
    # @param provider [Symbol, String] Extractor LLM provider.
    # @param model [String, nil] Optional provider model override.
    # @return [void]
    def check_context_suggestions(source_paths:, discovery_mode: :auto, translation_paths: nil,
                                  context_files: nil, include_pull_request_context: true,
                                  inline_mode: nil, summary: false, report_type: :message,
                                  provider: :anthropic, model: nil)
      @file_lines_cache = {}

      discovery_mode = normalize_enum_param(discovery_mode, VALID_DISCOVERY_MODES, 'discovery_mode')
      return if discovery_mode.nil?

      if inline_mode
        inline_mode = normalize_enum_param(inline_mode, VALID_INLINE_MODES, 'inline_mode')
        return if inline_mode.nil?
      end

      raw_validation_message = validate_raw_context_options(
        source_paths: source_paths,
        translation_paths: translation_paths,
        context_files: context_files,
        include_pull_request_context: include_pull_request_context
      )
      if raw_validation_message
        reporter.report(message: raw_validation_message, type: :warning)
        return
      end

      translation_paths = normalize_paths(translation_paths)
      configured_source_paths = normalize_paths(source_paths)
      context_files = normalize_paths(context_files)
      reporting_enabled = inline_mode != :none || summary

      validation_message = validate_context_configuration(
        discovery_mode: discovery_mode,
        source_paths: configured_source_paths,
        translation_paths: translation_paths,
        inline_mode: inline_mode,
        context_files: context_files,
        validate_paths: reporting_enabled
      )
      if validation_message
        reporter.report(message: validation_message, type: :warning)
        return
      end

      return unless reporting_enabled

      resolved_discovery_mode = resolved_discovery_mode(
        discovery_mode,
        source_paths: configured_source_paths,
        translation_paths: translation_paths
      )
      return unless resolved_discovery_mode

      resolved_inline_validation = validate_resolved_inline_mode(
        requested_discovery_mode: discovery_mode,
        resolved_discovery_mode: resolved_discovery_mode,
        inline_mode: inline_mode
      )
      if resolved_inline_validation
        reporter.report(message: resolved_inline_validation, type: :warning)
        return
      end

      inline_mode ||= default_inline_mode_for(discovery_mode: resolved_discovery_mode)
      results = extract_results(
        discovery_mode: resolved_discovery_mode,
        translation_paths: translation_paths,
        source_paths: configured_source_paths,
        provider: provider,
        model: model,
        context_files: context_files,
        include_pull_request_context: include_pull_request_context
      )
      return if results.nil? || results.empty?

      publish_results(results, inline_mode: inline_mode, summary: summary, report_type: report_type)
    end

    private

    def resolved_discovery_mode(discovery_mode, source_paths:, translation_paths:)
      changed_translation_files = select_changed_translation_files(translation_paths)
      changed_source_files = select_changed_source_files(
        source_paths,
        translation_paths: translation_paths
      )
      resolve_discovery_mode(
        discovery_mode,
        changed_translation_files: changed_translation_files,
        changed_source_files: changed_source_files
      )
    end

    def extract_results(discovery_mode:, translation_paths:, source_paths:, provider:, model:,
                        context_files:, include_pull_request_context:)
      supplemental_context = include_pull_request_context ? pull_request_context : {}
      run_extraction(
        discovery_mode: discovery_mode,
        translation_paths: discovery_mode == :translations ? translation_paths : [],
        source_paths: source_paths,
        provider: provider,
        model: model,
        context_files: context_files,
        supplemental_context: supplemental_context
      )
    rescue StandardError => e
      reporter.report(
        message: "Translation context extraction failed: #{e.message}",
        type: :warning
      )
      nil
    end

    def publish_results(results, inline_mode:, summary:, report_type:)
      failed_results, successful_results = results.partition(&:error)
      report_extraction_errors(failed_results)

      actionable_results = successful_results.select(&:actionable?)
      return if actionable_results.empty?

      if inline_reporting?(inline_mode)
        post_inline_comments(
          actionable_results,
          report_type,
          inline_mode: inline_mode
        )
      end
      post_summary_table(actionable_results) if summary
    end

    def select_changed_translation_files(translation_paths)
      changed_files = normalized_changed_files
      translation_paths.select { |path| changed_files.include?(path) }
    end

    def select_changed_source_files(source_paths, translation_paths:)
      changed_files = normalized_changed_files
      translation_files = Set.new(translation_paths)

      changed_files.reject { |path| translation_files.include?(path) }.select do |path|
        source_paths.any? { |source_path| path_matches_source_path?(path, source_path) }
      end
    end

    def path_matches_source_path?(path, source_path)
      normalized_source_path = normalize_path(source_path)
      return true if normalized_source_path == '.'

      path == normalized_source_path || path.start_with?("#{normalized_source_path}/")
    end

    def resolve_discovery_mode(discovery_mode, changed_translation_files:, changed_source_files:)
      case discovery_mode
      when :translations
        :translations unless changed_translation_files.empty?
      when :source
        :source unless changed_source_files.empty?
      else
        return :translations unless changed_translation_files.empty?

        :source unless changed_source_files.empty?
      end
    end

    def normalize_paths(paths)
      Array(paths).compact.map { |path| normalize_path(path) }.uniq
    end

    def paths_contain_blank?(paths)
      Array(paths).compact.any? { |path| path.to_s.strip.empty? }
    end

    def validate_raw_context_options(source_paths:, translation_paths:, context_files:,
                                     include_pull_request_context:)
      return 'include_pull_request_context must be true or false.' unless
        [true, false].include?(include_pull_request_context)

      {
        source_paths: source_paths,
        translation_paths: translation_paths,
        context_files: context_files
      }.each do |name, paths|
        return "#{name} must not contain blank paths." if paths_contain_blank?(paths)
      end

      nil
    end

    def normalize_path(path)
      Pathname.new(path.to_s).cleanpath.to_s
    end

    def normalized_changed_files
      git_utils.added_and_modified_files.map { |path| normalize_path(path) }
    end

    def pull_request_context
      {
        'Pull request title' => github.pr_title.to_s,
        'Pull request description' => github.pr_body.to_s
      }.reject do |_name, content|
        content.strip.empty?
      end
    end

    def validate_context_inputs(discovery_mode:, source_paths:, translation_paths:, inline_mode:)
      return 'source_paths is required for translation context suggestions.' if source_paths.empty?
      return 'translation_paths is not supported when discovery_mode is `source`.' if discovery_mode == :source && translation_paths.any?
      return 'translation_paths is required when discovery_mode is `translations`.' if discovery_mode == :translations && translation_paths.empty?
      return 'inline_mode `translation_comment` is not supported when discovery_mode is `source`.' if discovery_mode == :source && inline_mode == :translation_comment
      return 'inline_mode `translation_suggestion` is not supported when discovery_mode is `source`.' if discovery_mode == :source && inline_mode == :translation_suggestion
      return 'inline_mode `translation_comment` requires translation_paths.' if inline_mode == :translation_comment && translation_paths.empty?

      'inline_mode `translation_suggestion` requires translation_paths.' if inline_mode == :translation_suggestion && translation_paths.empty?
    end

    def validate_context_configuration(discovery_mode:, source_paths:, translation_paths:, inline_mode:,
                                       context_files:, validate_paths:)
      input_error = validate_context_inputs(
        discovery_mode: discovery_mode,
        source_paths: source_paths,
        translation_paths: translation_paths,
        inline_mode: inline_mode
      )
      return input_error if input_error
      return unless validate_paths

      validate_configured_paths(
        source_paths: source_paths,
        translation_paths: translation_paths,
        context_files: context_files
      )
    end

    def validate_configured_paths(source_paths:, translation_paths:, context_files: [])
      missing_paths = []
      source_paths.each { |path| missing_paths << [:source, path] unless File.exist?(path) }
      translation_paths.each { |path| missing_paths << [:translation, path] unless File.file?(path) }
      context_files.each { |path| missing_paths << [:context, path] unless File.file?(path) }
      return if missing_paths.empty?

      details = missing_paths.map { |type, path| "- #{type}: `#{path}`" }
      "Translation context configuration paths were not found:\n#{details.join("\n")}"
    end

    def validate_resolved_inline_mode(requested_discovery_mode:, resolved_discovery_mode:, inline_mode:)
      return unless requested_discovery_mode == :auto
      return unless resolved_discovery_mode == :source
      return unless %i[translation_comment translation_suggestion].include?(inline_mode)

      "inline_mode `#{inline_mode}` is not supported when `auto` resolves to source discovery."
    end

    def default_inline_mode_for(discovery_mode:)
      discovery_mode == :source ? :source_comment : :translation_comment
    end

    def normalize_enum_param(value, valid_values, param_name)
      normalized = value.to_sym if value.respond_to?(:to_sym)
      return normalized if normalized && valid_values.include?(normalized)

      reporter.report(
        message: "Invalid #{param_name} `#{value}`. Expected one of: #{valid_values.join(', ')}.",
        type: :warning
      )
      nil
    end
  end
end
