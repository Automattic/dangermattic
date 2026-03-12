# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Danger
  # Base class for LLM API providers. Handles HTTP communication with LLM APIs.
  # Not a Danger Plugin — used internally by LlmReviewer.
  #
  # @see Danger::LlmReviewer
  #
  class LlmProvider
    # Raised for general API errors (HTTP 5xx, unexpected responses, etc.)
    class ApiError < StandardError; end

    # Raised when authentication fails (HTTP 401/403 or missing API key)
    class AuthError < ApiError; end

    # Raised when the API rate limit is exceeded (HTTP 429)
    class RateLimitError < ApiError; end

    attr_reader :model, :api_key

    def initialize(model:, api_key:)
      @model = model
      @api_key = api_key
    end

    # Send a chat completion request to the LLM.
    #
    # @param system_prompt [String] The system prompt with instructions.
    # @param user_message [String] The user message with content to review.
    # @return [String] The raw text content of the LLM response.
    def chat(system_prompt:, user_message:)
      raise NotImplementedError, "#{self.class}#chat must be implemented"
    end

    # Factory method to create the appropriate provider instance.
    #
    # @param model [String] The model identifier (e.g., 'gpt-4o', 'claude-sonnet-4-20250514').
    # @param provider [Symbol, nil] Force a provider (:openai, :anthropic), or nil to auto-detect.
    # @return [LlmProvider] A provider instance ready to make API calls.
    def self.build(model:, provider: nil)
      resolved_provider = provider || detect_provider(model)

      case resolved_provider
      when :openai
        api_key = ENV.fetch('OPENAI_API_KEY') { raise AuthError, 'OPENAI_API_KEY environment variable is not set' }
        OpenAiProvider.new(model: model, api_key: api_key)
      when :anthropic
        api_key = ENV.fetch('ANTHROPIC_API_KEY') { raise AuthError, 'ANTHROPIC_API_KEY environment variable is not set' }
        AnthropicProvider.new(model: model, api_key: api_key)
      else
        raise ArgumentError,
              "Unknown LLM provider: #{resolved_provider}. Use :openai or :anthropic, or pass a model name that can be auto-detected."
      end
    end

    # Detect the provider from the model name.
    #
    # @param model [String] The model identifier.
    # @return [Symbol] :openai or :anthropic.
    def self.detect_provider(model)
      return :openai if model.match?(/^(gpt-|chatgpt-)/)
      return :anthropic if model.match?(/^claude/)

      raise ArgumentError,
            "Cannot auto-detect provider for model '#{model}'. Please specify provider: explicitly."
    end

    private

    def post_json(uri:, headers:, body:, timeout: 120)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = body.to_json

      response = http.request(request)

      case response.code.to_i
      when 200..299
        JSON.parse(response.body)
      when 401, 403
        raise AuthError, "Authentication failed (HTTP #{response.code})"
      when 429
        raise RateLimitError, 'Rate limit exceeded (HTTP 429)'
      else
        raise ApiError, "LLM API error (HTTP #{response.code})"
      end
    end
  end

  # OpenAI Chat Completions API provider.
  class OpenAiProvider < LlmProvider
    API_URL = 'https://api.openai.com/v1/chat/completions'

    def chat(system_prompt:, user_message:)
      uri = URI(API_URL)
      headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}"
      }
      body = {
        model: model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_message }
        ],
        temperature: 0.2,
        response_format: { type: 'json_object' }
      }

      result = post_json(uri: uri, headers: headers, body: body)
      result.dig('choices', 0, 'message', 'content') || ''
    end
  end

  # Anthropic Messages API provider.
  class AnthropicProvider < LlmProvider
    API_URL = 'https://api.anthropic.com/v1/messages'
    ANTHROPIC_VERSION = '2023-06-01'

    def chat(system_prompt:, user_message:)
      uri = URI(API_URL)
      headers = {
        'Content-Type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => ANTHROPIC_VERSION
      }
      body = {
        model: model,
        max_tokens: 4096,
        system: system_prompt,
        messages: [
          { role: 'user', content: user_message }
        ],
        temperature: 0.2
      }

      result = post_json(uri: uri, headers: headers, body: body)
      content_blocks = result['content'] || []
      text_block = content_blocks.find { |b| b['type'] == 'text' }
      text_block&.fetch('text', '') || ''
    end
  end
end
