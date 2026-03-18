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
    end
  end
end
