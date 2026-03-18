# frozen_string_literal: true

module Danger
  # Posts inline markdown comments, including multi-line GitHub review comments.
  #
  # This helper mirrors the API we want from Danger itself:
  # a markdown body with `file`, `line`, and optional range metadata.
  #
  # Today, released Danger only preserves `file` and `line` for inline markdown
  # comments, so range-aware suggestions still need a raw GitHub API fallback.
  # Once Danger supports ranged inline markdown comments natively, callers can
  # keep using this helper and the fallback path will no longer be needed.
  #
  # @example Post an inline suggestion using Danger when a single line is enough
  #   inline_markdown_poster.post(
  #     markdown: "```suggestion\n/* Context */\n\"Save\" = \"Save\";\n```",
  #     file: "Resources/Localizable.strings",
  #     line: 12
  #   )
  #
  # @see Automattic/dangermattic
  # @tags tool, util, github
  #
  class InlineMarkdownPoster < Plugin
    RAW_GITHUB_REVIEW_COMMENT_MARKER = '<!-- dangermattic-inline-markdown-poster -->'
    DEFAULT_SIDE = 'RIGHT'

    # Posts inline markdown, using native Danger support when available and
    # falling back to GitHub's ranged review comment API for multi-line ranges.
    #
    # @return [Boolean] true when the comment was posted successfully.
    def post(markdown:, file:, line:, start_line: nil, side: DEFAULT_SIDE, start_side: DEFAULT_SIDE)
      if start_line && !danger_supports_ranged_inline_markdown?
        upsert_raw_github_review_comment!(
          markdown,
          file: file,
          line: line,
          start_line: start_line,
          side: side,
          start_side: start_side
        )
      else
        danger.markdown(
          markdown,
          file: file,
          line: line,
          start_line: start_line,
          side: side,
          start_side: start_side
        )
      end
      true
    rescue StandardError
      false
    end

    private

    def danger_supports_ranged_inline_markdown?
      Danger::Markdown.instance_method(:initialize).parameters.any? do |type, name|
        %i[key keyreq].include?(type) && name == :start_line
      end
    end

    # Temporary bridge until Danger can post ranged inline markdown comments.
    # Callers use `post` either way, so migration back to pure Danger is a
    # helper-internal change once upstream support lands.
    def upsert_raw_github_review_comment!(markdown, file:, line:, start_line:, side:, start_side:)
      marked_body = raw_github_review_comment_body(markdown)
      matching_comments = fetch_pull_request_review_comments.select do |comment|
        raw_github_review_comment?(comment) &&
          same_raw_github_review_comment_location?(comment, file: file, line: line, start_line: start_line)
      end

      return if matching_comments.any? { |comment| comment['body'] == marked_body }

      if matching_comments.any?
        comment = matching_comments.shift
        github.api.update_pull_request_comment(github_repo_name, comment['id'], marked_body)

        matching_comments.each do |stale_comment|
          github.api.delete_pull_request_comment(github_repo_name, stale_comment['id'])
        end
      else
        github.api.create_pull_request_comment(
          github_repo_name,
          github_pull_request_number,
          marked_body,
          github_head_sha,
          file,
          line,
          start_line: start_line,
          side: side,
          start_side: start_side
        )
      end
    end

    def fetch_pull_request_review_comments
      github.api.pull_request_comments(github_repo_name, github_pull_request_number)
    end

    def raw_github_review_comment?(comment)
      comment['body'].to_s.include?(RAW_GITHUB_REVIEW_COMMENT_MARKER)
    end

    def same_raw_github_review_comment_location?(comment, file:, line:, start_line:)
      comment['path'] == file &&
        comment['line'].to_i == line &&
        comment['start_line'].to_i == start_line
    end

    def raw_github_review_comment_body(markdown)
      "#{RAW_GITHUB_REVIEW_COMMENT_MARKER}\n#{markdown}"
    end

    def github_repo_name
      github.pr_json['base']['repo']['full_name']
    end

    def github_pull_request_number
      github.pr_json['number']
    end

    def github_head_sha
      github.pr_json['head']['sha']
    end
  end
end
