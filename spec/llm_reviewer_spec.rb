# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::LlmReviewer do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.llm_reviewer

        @mock_api = double('Octokit::Client') # rubocop:disable RSpec/VerifiedDoubles
        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
        allow(@plugin.github).to receive_messages(
          pr_title: 'Test PR',
          pr_body: 'Test description',
          pr_json: {
            'head' => { 'sha' => 'abc123' },
            'base' => { 'repo' => { 'full_name' => 'owner/repo' } },
            'number' => 42
          },
          api: @mock_api
        )
        allow(@mock_api).to receive(:pull_request_comments).and_return([])
      end

      context 'when max_comments is invalid' do
        it 'raises ArgumentError for zero' do
          expect { @plugin.review(model: 'gpt-4o', max_comments: 0) }.to raise_error(ArgumentError, /max_comments/)
        end

        it 'raises ArgumentError for negative values' do
          expect { @plugin.review(model: 'gpt-4o', max_comments: -1) }.to raise_error(ArgumentError, /max_comments/)
        end
      end

      context 'when there are no changed files' do
        it 'does not call the LLM and reports nothing' do
          stub_env_keys
          allow(LlmProvider).to receive(:build)

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).not_to have_received(:build)
          expect(@dangerfile).to not_report
        end
      end

      context 'when reviewing changed files' do
        let(:diff_patch) do
          <<~DIFF
            @@ -1,3 +1,5 @@
             existing line
            +new line with bug
            +another new line
             more context
          DIFF
        end
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: ['app/helper.rb']
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: diff_patch)
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/helper.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: diff_patch)
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'posts inline warnings for valid findings' do
          llm_response = {
            'findings' => [
              { 'file' => 'app/main.rb', 'line' => 2, 'severity' => 'warning', 'message' => 'Potential null reference.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings]).to eq(['Potential null reference. <!-- llm-review:warning -->'])
        end

        it 'posts inline errors for error-severity findings' do
          llm_response = {
            'findings' => [
              { 'file' => 'app/main.rb', 'line' => 2, 'severity' => 'error', 'message' => 'SQL injection vulnerability.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:errors]).to eq(['SQL injection vulnerability. <!-- llm-review:error -->'])
        end

        it 'posts info messages for info-severity findings' do
          llm_response = {
            'findings' => [
              { 'file' => 'app/main.rb', 'line' => 2, 'severity' => 'info', 'message' => 'Consider adding a comment.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:messages]).to eq(['Consider adding a comment. <!-- llm-review:info -->'])
        end

        it 'reports nothing when LLM returns empty findings' do
          llm_response = { 'findings' => [] }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile).to not_report
        end
      end

      context 'when filtering files with file_selector' do
        let(:diff_patch) do
          <<~DIFF
            @@ -0,0 +1,3 @@
            +line one
            +line two
            +line three
          DIFF
        end
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb', 'app/style.css'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: diff_patch)
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/style.css')
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'only reviews files matching the file_selector' do
          llm_response = { 'findings' => [] }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', file_selector: ->(path) { path.end_with?('.rb') })

          expect(@plugin.git).not_to have_received(:diff_for_file).with('app/style.css')
        end
      end

      context 'when validating findings' do
        let(:diff_patch) do
          <<~DIFF
            @@ -1,3 +1,5 @@
             existing line
            +new line
            +another new line
             more context
          DIFF
        end
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: diff_patch)
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'drops findings that reference files not in the diff' do
          llm_response = {
            'findings' => [
              { 'file' => 'nonexistent.rb', 'line' => 1, 'severity' => 'warning', 'message' => 'Ghost finding.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile).to not_report
        end

        it 'demotes findings with invalid line numbers to general comments' do
          llm_response = {
            'findings' => [
              { 'file' => 'app/main.rb', 'line' => 999, 'severity' => 'warning', 'message' => 'Issue at wrong line.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings]).to eq(['Issue at wrong line. (in `app/main.rb`) <!-- llm-review:warning -->'])
        end
      end

      context 'when handling malformed JSON responses' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: "@@ -0,0 +1,1 @@\n+new line\n")
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'posts a warning when the response is not valid JSON' do
          allow(mock_provider).to receive(:chat).and_return('This is not JSON at all')

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings].first).to include('Could not parse the LLM response')
        end

        it 'handles JSON wrapped in markdown code fences' do
          fenced_response = "```json\n{\"findings\": [{\"file\": \"app/main.rb\", \"line\": 1, \"severity\": \"info\", \"message\": \"Test.\"}]}\n```"
          allow(mock_provider).to receive(:chat).and_return(fenced_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:messages]).to eq(['Test. <!-- llm-review:info -->'])
        end
      end

      context 'when handling API errors' do
        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: "@@ -0,0 +1,1 @@\n+new line\n")
          )
        end

        it 'reports a warning on AuthError' do
          allow(LlmProvider).to receive(:build).and_raise(LlmProvider::AuthError, 'OPENAI_API_KEY environment variable is not set')

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings].first).to include('Authentication failed')
        end

        it 'reports a warning on RateLimitError' do
          mock_provider = instance_double(OpenAiProvider)
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
          allow(mock_provider).to receive(:chat).and_raise(LlmProvider::RateLimitError, 'Rate limit exceeded')

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings].first).to include('Rate limit exceeded')
        end

        it 'reports a warning on ApiError' do
          mock_provider = instance_double(OpenAiProvider)
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
          allow(mock_provider).to receive(:chat).and_raise(LlmProvider::ApiError, 'LLM API error (HTTP 500)')

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings].first).to include('API error occurred')
        end

        it 'reports a warning on unexpected errors' do
          mock_provider = instance_double(OpenAiProvider)
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
          allow(mock_provider).to receive(:chat).and_raise(StandardError, 'something went wrong')

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings].first).to include('Unexpected error')
        end
      end

      context 'when capping findings' do
        let(:diff_patch) do
          <<~DIFF
            @@ -0,0 +1,3 @@
            +line one
            +line two
            +line three
          DIFF
        end
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: diff_patch)
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'limits the number of warnings to max_comments' do
          findings = (1..5).map do |i|
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'warning', 'message' => "Finding #{i}." }
          end
          llm_response = { 'findings' => findings }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', max_comments: 2)

          expect(@dangerfile.status_report[:warnings].length).to eq(2)
        end

        it 'adds a summary message when findings are omitted' do
          findings = (1..5).map do |i|
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'warning', 'message' => "Finding #{i}." }
          end
          llm_response = { 'findings' => findings }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', max_comments: 2)

          expect(@dangerfile.status_report[:messages].first).to include('3 additional finding(s) were omitted')
        end

        it 'keeps errors over warnings when capping' do
          findings = [
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'info', 'message' => 'Info finding.' },
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'error', 'message' => 'Error finding.' },
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'warning', 'message' => 'Warning finding.' }
          ]
          llm_response = { 'findings' => findings }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', max_comments: 2)

          expect(@dangerfile.status_report[:errors]).to eq(['Error finding. <!-- llm-review:error -->'])
        end

        it 'keeps warnings over info when capping' do
          findings = [
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'info', 'message' => 'Info finding.' },
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'error', 'message' => 'Error finding.' },
            { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'warning', 'message' => 'Warning finding.' }
          ]
          llm_response = { 'findings' => findings }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', max_comments: 2)

          expect(@dangerfile.status_report[:warnings]).to eq(['Warning finding. <!-- llm-review:warning -->'])
        end
      end

      context 'when using custom_prompt' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: "@@ -0,0 +1,1 @@\n+new line\n")
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'appends custom_prompt to the system prompt' do
          llm_response = { 'findings' => [] }.to_json
          captured_system_prompt = nil

          allow(mock_provider).to receive(:chat) do |system_prompt:, **_rest|
            captured_system_prompt = system_prompt
            llm_response
          end

          @plugin.review(model: 'gpt-4o', custom_prompt: 'Focus on memory leaks.')

          expect(captured_system_prompt).to include('Focus on memory leaks.')
        end

        it 'does not include PR content in the system prompt' do
          llm_response = { 'findings' => [] }.to_json
          captured_system_prompt = nil

          allow(mock_provider).to receive(:chat) do |system_prompt:, **_rest|
            captured_system_prompt = system_prompt
            llm_response
          end

          @plugin.review(model: 'gpt-4o')

          expect(captured_system_prompt).not_to include('Test PR')
        end
      end

      context 'when annotating diffs with line numbers' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'annotates added lines with new-file line numbers' do # rubocop:disable RSpec/MultipleExpectations
          patch = "@@ -0,0 +1,3 @@\n+line one\n+line two\n+line three\n"
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: patch)
          )
          captured_user_message = nil
          allow(mock_provider).to receive(:chat) do |user_message:, **_rest|
            captured_user_message = user_message
            { 'findings' => [] }.to_json
          end

          @plugin.review(model: 'gpt-4o')

          expect(captured_user_message).to include('[L1] +line one')
          expect(captured_user_message).to include('[L2] +line two')
          expect(captured_user_message).to include('[L3] +line three')
        end

        it 'annotates context lines and skips removed lines' do # rubocop:disable RSpec/MultipleExpectations
          patch = "@@ -10,4 +10,4 @@\n context\n-old line\n+new line\n more context\n"
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: patch)
          )
          captured_user_message = nil
          allow(mock_provider).to receive(:chat) do |user_message:, **_rest|
            captured_user_message = user_message
            { 'findings' => [] }.to_json
          end

          @plugin.review(model: 'gpt-4o')

          expect(captured_user_message).to include('[L10]  context')
          expect(captured_user_message).to include('[L11] +new line')
          expect(captured_user_message).to include('[L12]  more context')
          expect(captured_user_message).to include('-old line')
          expect(captured_user_message).not_to match(/\[L\d+\].*old line/)
        end
      end

      context 'when diff exceeds max_diff_size' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          large_patch = "@@ -0,0 +1,1 @@\n+#{'x' * 2000}\n"
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: large_patch)
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'posts a message about truncation when diff is too large' do
          llm_response = { 'findings' => [] }.to_json
          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o', max_diff_size: 100)

          expect(@dangerfile.status_report[:messages]).to include(
            'LLM Reviewer: The diff was too large to review in full. Only a subset of files was reviewed.'
          )
        end
      end

      context 'when handling unknown severity values' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: "@@ -0,0 +1,1 @@\n+new line\n")
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'defaults unknown severity to warning during parsing' do
          llm_response = {
            'findings' => [
              { 'file' => 'app/main.rb', 'line' => 1, 'severity' => 'critical', 'message' => 'Unknown severity finding.' }
            ]
          }.to_json

          allow(mock_provider).to receive(:chat).and_return(llm_response)

          @plugin.review(model: 'gpt-4o')

          expect(@dangerfile.status_report[:warnings]).to eq(['Unknown severity finding. <!-- llm-review:warning -->'])
        end
      end

      context 'when caching findings from previous runs' do
        let(:mock_provider) { instance_double(OpenAiProvider) }

        before do
          allow(@plugin.git).to receive_messages(
            added_files: ['app/main.rb'],
            modified_files: []
          )
          allow(@plugin.git).to receive(:diff_for_file).with('app/main.rb').and_return(
            instance_double(Git::Diff::DiffFile, patch: "@@ -0,0 +1,1 @@\n+new line\n")
          )
          stub_env_keys
          allow(LlmProvider).to receive(:build).and_return(mock_provider)
        end

        it 'replays cached findings and skips the LLM call' do
          cached_comment = double( # rubocop:disable RSpec/VerifiedDoubles
            'ReviewComment',
            commit_id: 'abc123',
            path: 'app/main.rb',
            line: 1,
            body: "<td>\n\nSome issue. <!-- llm-review:warning -->\n\n</td>"
          )
          allow(@mock_api).to receive(:pull_request_comments).and_return([cached_comment])

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).not_to have_received(:build)
          expect(@dangerfile.status_report[:warnings]).to eq(['Some issue. <!-- llm-review:warning -->'])
        end

        it 'calls the LLM when no cached findings exist for this SHA' do
          allow(mock_provider).to receive(:chat).and_return({ 'findings' => [] }.to_json)

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).to have_received(:build)
        end

        it 'ignores cached comments from a different commit' do
          stale_comment = double( # rubocop:disable RSpec/VerifiedDoubles
            'ReviewComment',
            commit_id: 'old_sha',
            path: 'app/main.rb',
            line: 1,
            body: "<td>\n\nStale. <!-- llm-review:warning -->\n\n</td>"
          )
          allow(@mock_api).to receive(:pull_request_comments).and_return([stale_comment])
          allow(mock_provider).to receive(:chat).and_return({ 'findings' => [] }.to_json)

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).to have_received(:build)
        end

        it 'ignores comments without the LLM review tag' do
          other_comment = double( # rubocop:disable RSpec/VerifiedDoubles
            'ReviewComment',
            commit_id: 'abc123',
            path: 'app/main.rb',
            line: 1,
            body: '<td>Some other plugin comment</td>'
          )
          allow(@mock_api).to receive(:pull_request_comments).and_return([other_comment])
          allow(mock_provider).to receive(:chat).and_return({ 'findings' => [] }.to_json)

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).to have_received(:build)
        end

        it 'falls through to fresh review when cache check fails' do
          allow(@mock_api).to receive(:pull_request_comments).and_raise(StandardError, 'API error')
          allow(mock_provider).to receive(:chat).and_return({ 'findings' => [] }.to_json)

          @plugin.review(model: 'gpt-4o')

          expect(LlmProvider).to have_received(:build)
        end
      end
    end
  end
end

def stub_env_keys
  allow(ENV).to receive(:fetch).and_call_original
  allow(ENV).to receive(:fetch).with('OPENAI_API_KEY').and_return('test-openai-key')
  allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY').and_return('test-anthropic-key')
end
