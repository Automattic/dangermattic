# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe LlmProvider do
    describe '.detect_provider' do
      it 'detects OpenAI from gpt- prefix' do
        expect(described_class.detect_provider('gpt-4o')).to eq(:openai)
      end

      it 'detects OpenAI from chatgpt- prefix' do
        expect(described_class.detect_provider('chatgpt-4o-latest')).to eq(:openai)
      end

      it 'detects Anthropic from claude prefix' do
        expect(described_class.detect_provider('claude-sonnet-4-20250514')).to eq(:anthropic)
      end

      it 'raises for unknown model names' do
        expect { described_class.detect_provider('llama-3') }.to raise_error(ArgumentError, /Cannot auto-detect/)
      end

      it 'raises for o-series models that need explicit provider' do
        expect { described_class.detect_provider('o3-mini') }.to raise_error(ArgumentError, /Cannot auto-detect/)
      end
    end

    describe '.build' do
      context 'with OpenAI' do
        it 'creates an OpenAiProvider when OPENAI_API_KEY is set' do
          stub_env('OPENAI_API_KEY', 'test-key')
          provider = described_class.build(model: 'gpt-4o')
          expect(provider).to be_a(OpenAiProvider)
          expect(provider.model).to eq('gpt-4o')
        end

        it 'raises AuthError when OPENAI_API_KEY is missing' do
          stub_env('OPENAI_API_KEY', nil)
          expect { described_class.build(model: 'gpt-4o') }.to raise_error(LlmProvider::AuthError, /OPENAI_API_KEY/)
        end
      end

      context 'with Anthropic' do
        it 'creates an AnthropicProvider when ANTHROPIC_API_KEY is set' do
          stub_env('ANTHROPIC_API_KEY', 'test-key')
          provider = described_class.build(model: 'claude-sonnet-4-20250514')
          expect(provider).to be_a(AnthropicProvider)
          expect(provider.model).to eq('claude-sonnet-4-20250514')
        end

        it 'raises AuthError when ANTHROPIC_API_KEY is missing' do
          stub_env('ANTHROPIC_API_KEY', nil)
          expect { described_class.build(model: 'claude-sonnet-4-20250514') }.to raise_error(LlmProvider::AuthError, /ANTHROPIC_API_KEY/)
        end
      end

      context 'with explicit provider' do
        it 'uses the specified provider instead of auto-detecting' do
          stub_env('ANTHROPIC_API_KEY', 'test-key')
          provider = described_class.build(model: 'my-custom-model', provider: :anthropic)
          expect(provider).to be_a(AnthropicProvider)
        end

        it 'raises for unknown provider symbols' do
          expect { described_class.build(model: 'test', provider: :gemini) }.to raise_error(ArgumentError, /Unknown LLM provider/)
        end
      end
    end
  end

  describe OpenAiProvider do
    subject(:provider) { described_class.new(model: 'gpt-4o', api_key: 'test-key') }

    describe '#chat' do
      it 'sends the correct request and extracts the response content' do
        response_body = {
          'choices' => [{ 'message' => { 'content' => '{"findings": []}' } }]
        }
        stub_successful_http_response(response_body)

        result = provider.chat(system_prompt: 'You are a reviewer.', user_message: 'Review this code.')
        expect(result).to eq('{"findings": []}')
      end

      it 'returns empty string when response has no content' do
        response_body = { 'choices' => [{ 'message' => {} }] }
        stub_successful_http_response(response_body)

        result = provider.chat(system_prompt: 'test', user_message: 'test')
        expect(result).to eq('')
      end

      it 'raises AuthError on HTTP 401' do
        stub_http_error_response(401)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::AuthError)
      end

      it 'raises RateLimitError on HTTP 429' do
        stub_http_error_response(429)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::RateLimitError)
      end

      it 'raises ApiError on HTTP 500' do
        stub_http_error_response(500)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::ApiError)
      end
    end
  end

  describe AnthropicProvider do
    subject(:provider) { described_class.new(model: 'claude-sonnet-4-20250514', api_key: 'test-key') }

    describe '#chat' do
      it 'sends the correct request and extracts the response content' do
        response_body = {
          'content' => [{ 'type' => 'text', 'text' => '{"findings": []}' }]
        }
        stub_successful_http_response(response_body)

        result = provider.chat(system_prompt: 'You are a reviewer.', user_message: 'Review this code.')
        expect(result).to eq('{"findings": []}')
      end

      it 'returns empty string when response has no text block' do
        response_body = { 'content' => [] }
        stub_successful_http_response(response_body)

        result = provider.chat(system_prompt: 'test', user_message: 'test')
        expect(result).to eq('')
      end

      it 'raises AuthError on HTTP 401' do
        stub_http_error_response(401)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::AuthError)
      end

      it 'raises RateLimitError on HTTP 429' do
        stub_http_error_response(429)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::RateLimitError)
      end

      it 'raises ApiError on HTTP 500' do
        stub_http_error_response(500)
        expect { provider.chat(system_prompt: 'test', user_message: 'test') }.to raise_error(LlmProvider::ApiError)
      end
    end
  end
end

def stub_env(key, value)
  if value.nil?
    allow(ENV).to receive(:fetch).with(key).and_call_original
    allow(ENV).to receive(:fetch).with(key) { |_k, &block| block ? block.call : raise(KeyError) }
  else
    allow(ENV).to receive(:fetch).with(key).and_return(value)
  end
end

def stub_successful_http_response(body)
  response = instance_double(Net::HTTPResponse, code: '200', body: body.to_json)
  http = double('Net::HTTP') # rubocop:disable RSpec/VerifiedDoubles
  allow(http).to receive(:'use_ssl=')
  allow(http).to receive(:'open_timeout=')
  allow(http).to receive(:'read_timeout=')
  allow(http).to receive(:request).and_return(response)
  allow(Net::HTTP).to receive(:new).and_return(http)
end

def stub_http_error_response(code)
  response = instance_double(Net::HTTPResponse, code: code.to_s, body: 'error')
  http = double('Net::HTTP') # rubocop:disable RSpec/VerifiedDoubles
  allow(http).to receive(:'use_ssl=')
  allow(http).to receive(:'open_timeout=')
  allow(http).to receive(:'read_timeout=')
  allow(http).to receive(:request).and_return(response)
  allow(Net::HTTP).to receive(:new).and_return(http)
end
