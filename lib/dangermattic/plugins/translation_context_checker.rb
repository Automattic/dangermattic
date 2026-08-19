# frozen_string_literal: true

require 'pathname'
# Used by the included components; keep this entry point independent of transitive requires.
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
  #   translation_context_checker.check_source_changes(
  #     source_paths: ['Sources/'],
  #     inline_mode: :source_suggestion
  #   )
  #
  # @example Resource-backed Android suggestions
  #   translation_context_checker.check_resource_changes(
  #     source_paths: ['app/src/main/java/'],
  #     resource_paths: ['app/src/main/res/values/strings.xml']
  #   )
  #
  # @see Automattic/dangermattic
  # @tags localization, translation, context
  class TranslationContextChecker < Plugin
    include TranslationContextCheckerExtraction
    include TranslationContextCheckerLocationResolver
    include TranslationContextCheckerPublisher
    include TranslationContextCheckerSuggestionRenderer

    VALID_INLINE_MODES = %i[
      translation_comment
      translation_suggestion
      source_comment
      source_suggestion
      none
    ].freeze
    SWIFT_COMMENT_ARGUMENT_PATTERN = /comment:\s*"((?:\\.|[^"\\])*)"/

    # Analyze localization keys changed in source code.
    #
    # @param source_paths [String, Array<String>] Explicit source search scope.
    # @param context_files [String, Array<String>, nil] Free-form files included in full as untrusted evidence.
    # @param include_pull_request_context [Boolean] Include the PR title and description as untrusted evidence.
    # @param inline_mode [Symbol, String, nil] Inline comment/suggestion target.
    # @param summary [Boolean] Whether to add a PR-level summary table.
    # @param report_type [Symbol] Severity for PR-level fallback reports.
    # @param provider [Symbol, String] Extractor LLM provider.
    # @param model [String, nil] Optional provider model override.
    # @return [void]
    def check_source_changes(source_paths:, context_files: nil, include_pull_request_context: true,
                             inline_mode: nil, summary: false, report_type: :message,
                             provider: :anthropic, model: nil)
      check_changes(
        discovery_mode: :source,
        source_paths: source_paths,
        resource_paths: [],
        context_files: context_files,
        include_pull_request_context: include_pull_request_context,
        inline_mode: inline_mode,
        summary: summary,
        report_type: report_type,
        provider: provider,
        model: model
      )
    end

    # Analyze localization keys changed in source-language resource files.
    #
    # Source code is still searched for usage context.
    #
    # @param resource_paths [String, Array<String>] Source-language localization files.
    # @param source_paths [String, Array<String>] Explicit source search scope.
    # @param context_files [String, Array<String>, nil] Free-form files included in full as untrusted evidence.
    # @param include_pull_request_context [Boolean] Include the PR title and description as untrusted evidence.
    # @param inline_mode [Symbol, String, nil] Inline comment/suggestion target.
    # @param summary [Boolean] Whether to add a PR-level summary table.
    # @param report_type [Symbol] Severity for PR-level fallback reports.
    # @param provider [Symbol, String] Extractor LLM provider.
    # @param model [String, nil] Optional provider model override.
    # @return [void]
    def check_resource_changes(resource_paths:, source_paths:, context_files: nil,
                               include_pull_request_context: true, inline_mode: nil,
                               summary: false, report_type: :message,
                               provider: :anthropic, model: nil)
      check_changes(
        discovery_mode: :translations,
        source_paths: source_paths,
        resource_paths: resource_paths,
        context_files: context_files,
        include_pull_request_context: include_pull_request_context,
        inline_mode: inline_mode,
        summary: summary,
        report_type: report_type,
        provider: provider,
        model: model
      )
    end

    private

    def check_changes(discovery_mode:, source_paths:, resource_paths:, context_files:,
                      include_pull_request_context:, inline_mode:, summary:, report_type:,
                      provider:, model:)
      @file_lines_cache = {}

      if inline_mode
        inline_mode = normalize_enum_param(inline_mode, VALID_INLINE_MODES, 'inline_mode')
        return if inline_mode.nil?
      end

      raw_validation_message = validate_raw_context_options(
        source_paths: source_paths,
        resource_paths: resource_paths,
        context_files: context_files,
        include_pull_request_context: include_pull_request_context
      )
      if raw_validation_message
        reporter.report(message: raw_validation_message, type: :warning)
        return
      end

      resource_paths = normalize_paths(resource_paths)
      configured_source_paths = normalize_paths(source_paths)
      context_files = normalize_paths(context_files)
      reporting_enabled = inline_mode != :none || summary

      validation_message = validate_context_configuration(
        discovery_mode: discovery_mode,
        source_paths: configured_source_paths,
        resource_paths: resource_paths,
        inline_mode: inline_mode,
        context_files: context_files,
        validate_paths: reporting_enabled
      )
      if validation_message
        reporter.report(message: validation_message, type: :warning)
        return
      end

      return unless reporting_enabled
      return unless relevant_files_changed?(
        discovery_mode: discovery_mode,
        source_paths: configured_source_paths,
        resource_paths: resource_paths
      )

      inline_mode ||= default_inline_mode_for(discovery_mode: discovery_mode)
      results = extract_results(
        discovery_mode: discovery_mode,
        resource_paths: resource_paths,
        source_paths: configured_source_paths,
        provider: provider,
        model: model,
        context_files: context_files,
        include_pull_request_context: include_pull_request_context
      )
      return if results.nil? || results.empty?

      publish_results(results, inline_mode: inline_mode, summary: summary, report_type: report_type)
    end

    def extract_results(discovery_mode:, resource_paths:, source_paths:, provider:, model:,
                        context_files:, include_pull_request_context:)
      supplemental_context = include_pull_request_context ? pull_request_context : {}
      run_extraction(
        discovery_mode: discovery_mode,
        translation_paths: resource_paths,
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

    def relevant_files_changed?(discovery_mode:, source_paths:, resource_paths:)
      changed_files = if discovery_mode == :source
                        select_changed_source_files(source_paths)
                      else
                        select_changed_resource_files(resource_paths)
                      end
      changed_files.any?
    end

    def select_changed_resource_files(resource_paths)
      changed_files = normalized_changed_files
      resource_paths.select { |path| changed_files.include?(path) }
    end

    def select_changed_source_files(source_paths)
      changed_files = normalized_changed_files
      changed_files.select do |path|
        source_paths.any? { |source_path| path_matches_source_path?(path, source_path) }
      end
    end

    def path_matches_source_path?(path, source_path)
      normalized_source_path = normalize_path(source_path)
      return true if normalized_source_path == '.'

      path == normalized_source_path || path.start_with?("#{normalized_source_path}/")
    end

    def normalize_paths(paths)
      Array(paths).compact.map { |path| normalize_path(path) }.uniq
    end

    def paths_contain_blank?(paths)
      Array(paths).compact.any? { |path| path.to_s.strip.empty? }
    end

    def validate_raw_context_options(source_paths:, resource_paths:, context_files:,
                                     include_pull_request_context:)
      return 'include_pull_request_context must be true or false.' unless
        [true, false].include?(include_pull_request_context)

      {
        source_paths: source_paths,
        resource_paths: resource_paths,
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

    def validate_context_inputs(discovery_mode:, source_paths:, resource_paths:, inline_mode:)
      return 'source_paths is required for translation context suggestions.' if source_paths.empty?
      return 'resource_paths is required for resource changes.' if discovery_mode == :translations && resource_paths.empty?
      return 'inline_mode `translation_comment` is not supported for source changes.' if discovery_mode == :source && inline_mode == :translation_comment
      return 'inline_mode `translation_suggestion` is not supported for source changes.' if discovery_mode == :source && inline_mode == :translation_suggestion

      nil
    end

    def validate_context_configuration(discovery_mode:, source_paths:, resource_paths:, inline_mode:,
                                       context_files:, validate_paths:)
      input_error = validate_context_inputs(
        discovery_mode: discovery_mode,
        source_paths: source_paths,
        resource_paths: resource_paths,
        inline_mode: inline_mode
      )
      return input_error if input_error
      return unless validate_paths

      validate_configured_paths(
        source_paths: source_paths,
        resource_paths: resource_paths,
        context_files: context_files
      )
    end

    def validate_configured_paths(source_paths:, resource_paths:, context_files: [])
      missing_paths = []
      source_paths.each { |path| missing_paths << [:source, path] unless File.exist?(path) }
      resource_paths.each { |path| missing_paths << [:resource, path] unless File.file?(path) }
      context_files.each { |path| missing_paths << [:context, path] unless File.file?(path) }
      return if missing_paths.empty?

      details = missing_paths.map { |type, path| "- #{type}: `#{path}`" }
      "Translation context configuration paths were not found:\n#{details.join("\n")}"
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
