# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::InlineMarkdownPoster do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe '#post' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.inline_markdown_poster
      end

      it 'uses the normal Danger markdown path for single-line comments' do
        @plugin.post(
          markdown: '```suggestion\ncomment\n```',
          file: 'Localizable.strings',
          line: 2
        )

        expect(@dangerfile.status_report[:markdowns].map(&:message)).to eq(['```suggestion\ncomment\n```'])
      end

      it 'uses the normal Danger markdown path for ranged comments when Danger supports them' do
        allow(@plugin).to receive(:danger_supports_ranged_inline_markdown?).and_return(true)
        allow(@plugin.danger).to receive(:markdown)

        @plugin.post(
          markdown: '```suggestion\ncomment\n```',
          file: 'Localizable.strings',
          line: 3,
          start_line: 2
        )

        expect(@plugin.danger).to have_received(:markdown).with(
          '```suggestion\ncomment\n```',
          file: 'Localizable.strings',
          line: 3,
          start_line: 2
        )
      end

      it 'falls back to the GitHub review comment API for ranged comments when Danger does not support them' do
        github_api = instance_double(Octokit::Client)
        github_plugin = instance_double(
          Danger::DangerfileGitHubPlugin,
          pr_json: {
            'base' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } },
            'number' => 42,
            'head' => { 'sha' => 'abc123' }
          },
          api: github_api
        )

        allow(@plugin).to receive_messages(
          github: github_plugin,
          danger_supports_ranged_inline_markdown?: false
        )
        allow(github_api).to receive_messages(
          pull_request_comments: [],
          create_pull_request_comment: {}
        )

        @plugin.post(
          markdown: <<~MARKDOWN.chomp,
            ```suggestion
            comment
            ```
          MARKDOWN
          file: 'Localizable.strings',
          line: 3,
          start_line: 2,
          side: 'RIGHT',
          start_side: 'RIGHT'
        )

        expect(github_api).to have_received(:create_pull_request_comment).with(
          'Automattic/dangermattic',
          42,
          <<~MARKDOWN.chomp,
            <!-- dangermattic-inline-markdown-poster -->
            ```suggestion
            comment
            ```
          MARKDOWN
          'abc123',
          'Localizable.strings',
          3,
          start_line: 2,
          side: 'RIGHT',
          start_side: 'RIGHT'
        )
      end

      context 'with raw GitHub review comment upsert logic' do
        let(:github_api) { instance_double(Octokit::Client) }
        let(:github_plugin) do
          instance_double(
            Danger::DangerfileGitHubPlugin,
            pr_json: {
              'base' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } },
              'number' => 42,
              'head' => { 'sha' => 'abc123' }
            },
            api: github_api
          )
        end

        before do
          allow(@plugin).to receive_messages(
            github: github_plugin,
            danger_supports_ranged_inline_markdown?: false
          )
        end

        it 'detects ranged inline markdown support from the Danger markdown signature' do
          markdown_initializer = instance_double(UnboundMethod, parameters: [%i[req message], %i[key start_line]])

          allow(@plugin).to receive(:danger_supports_ranged_inline_markdown?).and_call_original
          allow(Danger::Markdown).to receive(:instance_method).with(:initialize).and_return(markdown_initializer)

          expect(@plugin.send(:danger_supports_ranged_inline_markdown?)).to be true
        end

        it 'skips when an identical comment already exists' do
          existing_comment = {
            'id' => 100,
            'body' => "<!-- dangermattic-inline-markdown-poster -->\ncontent",
            'path' => 'Localizable.strings',
            'line' => 3,
            'start_line' => 2
          }
          allow(github_api).to receive_messages(
            pull_request_comments: [existing_comment],
            create_pull_request_comment: {},
            update_pull_request_comment: {},
            delete_pull_request_comment: {}
          )

          result = @plugin.post(
            markdown: 'content',
            file: 'Localizable.strings',
            line: 3,
            start_line: 2
          )

          expect(result).to be true
          expect(github_api).not_to have_received(:create_pull_request_comment)
        end

        it 'ignores unmanaged comments at the same location' do
          human_comment = {
            'id' => 100,
            'body' => 'Human review comment',
            'path' => 'Localizable.strings',
            'line' => 3,
            'start_line' => 2
          }
          allow(github_api).to receive_messages(
            pull_request_comments: [human_comment],
            create_pull_request_comment: {}
          )

          @plugin.post(
            markdown: 'managed content',
            file: 'Localizable.strings',
            line: 3,
            start_line: 2
          )

          expect(github_api).to have_received(:create_pull_request_comment).with(
            'Automattic/dangermattic',
            42,
            "<!-- dangermattic-inline-markdown-poster -->\nmanaged content",
            'abc123',
            'Localizable.strings',
            3,
            start_line: 2,
            side: 'RIGHT',
            start_side: 'RIGHT'
          )
        end

        it 'updates an existing comment with different body' do
          existing_comment = {
            'id' => 100,
            'body' => "<!-- dangermattic-inline-markdown-poster -->\nold content",
            'path' => 'Localizable.strings',
            'line' => 3,
            'start_line' => 2
          }
          allow(github_api).to receive_messages(
            pull_request_comments: [existing_comment],
            update_pull_request_comment: {}
          )

          @plugin.post(
            markdown: 'new content',
            file: 'Localizable.strings',
            line: 3,
            start_line: 2
          )

          expect(github_api).to have_received(:update_pull_request_comment).with(
            'Automattic/dangermattic',
            100,
            "<!-- dangermattic-inline-markdown-poster -->\nnew content"
          )
        end

        it 'cleans up stale duplicate comments' do
          stale_comments = [
            {
              'id' => 100,
              'body' => "<!-- dangermattic-inline-markdown-poster -->\nold 1",
              'path' => 'Localizable.strings',
              'line' => 3,
              'start_line' => 2
            },
            {
              'id' => 101,
              'body' => "<!-- dangermattic-inline-markdown-poster -->\nold 2",
              'path' => 'Localizable.strings',
              'line' => 3,
              'start_line' => 2
            }
          ]
          allow(github_api).to receive_messages(
            pull_request_comments: stale_comments,
            update_pull_request_comment: {},
            delete_pull_request_comment: {}
          )

          @plugin.post(
            markdown: 'new content',
            file: 'Localizable.strings',
            line: 3,
            start_line: 2
          )

          expect(github_api).to have_received(:update_pull_request_comment).with(
            'Automattic/dangermattic',
            100,
            "<!-- dangermattic-inline-markdown-poster -->\nnew content"
          )
          expect(github_api).to have_received(:delete_pull_request_comment).with(
            'Automattic/dangermattic',
            101
          )
        end

        it 'returns false when the API call fails' do
          allow(github_api).to receive(:pull_request_comments).and_raise(Octokit::NotFound)

          result = @plugin.post(
            markdown: 'content',
            file: 'Localizable.strings',
            line: 3,
            start_line: 2
          )

          expect(result).to be false
        end
      end
    end
  end
end
