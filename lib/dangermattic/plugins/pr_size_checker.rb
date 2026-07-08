# frozen_string_literal: true

module Danger
  # Plugin to check the size of a Pull Request content and text body.
  #
  # @example Running a PR diff size check with default parameters
  #
  #          # Check the total size of changes in the PR using the default parameters, reporting a warning if the PR is larger than 500
  #          pr_size_checker.check_diff_size(max_size: 500)
  #
  # @example Running a PR diff size check customizing the size, message and type of report
  #
  #          # Check the total size of changes in the PR, reporting an error if the diff is larger than 1000 using the specified message
  #          pr_size_checker.check_diff_size(max_size: 1000, message: 'PR too large, 1000 is the max!!', report_type: :error)
  #
  # @example Running a PR diff size check on the specified files in part of the diff
  #
  #          # Check the size of insertions in the files selected by the file_selector
  #          pr_size_checker.check_diff_size(file_selector: ->(file) { file.include?('/java/test/') }, type: :insertions)
  #
  # @example Running a PR diff size check that excludes comment and blank lines from the count
  #
  #          # Only count changed lines that are neither blank nor comments (e.g. Kotlin/Java/Swift)
  #          pr_size_checker.check_diff_size(
  #            max_size: 300,
  #            line_selector: ->(line) { stripped = line.strip; !(stripped.empty? || stripped.start_with?('//', '/*', '*', '*/')) }
  #          )
  #
  # @example Running a PR description length check
  #
  #          # Check the PR Body using the default parameters, reporting a warning if the PR is smaller than 10 characters
  #          pr_size_checker.check_pr_body(min_length: 10)
  #
  # @example Running a PR description length check with custom parameters
  #
  #          # Check if the minimum length of the PR body is smaller than 20 characters, reporting an error using a custom error message
  #          pr_size_checker.check_pr_body(min_length: 20, message: 'Add a better description, 20 chars at least!!', report_type: :error)
  #
  # @see Automattic/dangermattic
  # @tags github, pull request, process
  #
  class PRSizeChecker < Plugin
    DEFAULT_DIFF_SIZE_MESSAGE_FORMAT = 'This PR is larger than %d lines of changes. Please consider splitting it into smaller PRs for easier and faster reviews.'
    DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT = 'The PR description appears very short, less than %d characters long. Please provide a summary of your changes in the PR description.'

    # Check the size of the PR diff against a specified maximum size.
    #
    # @param max_size [Integer] The maximum allowed size for the diff.
    # @param file_selector [Proc] Optional closure to filter the files in the diff to be used for size calculation.
    # @param line_selector [Proc] Optional closure to filter the individual changed lines counted towards the size.
    #   It receives the content of an added/removed line (without the leading `+`/`-` diff marker or trailing newline)
    #   and should return `true` for lines that should be counted. When provided, the size is computed by iterating the
    #   diff patches instead of the cached numstats, which is slower but allows excluding lines such as comments or blanks.
    # @param type [:insertions, :deletions, :all] The type of diff size to check. (default: :all)
    # @param message [String] The message to display if the diff size exceeds the maximum. (default: DEFAULT_DIFF_SIZE_MESSAGE)
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_diff_size(max_size:, file_selector: nil, line_selector: nil, type: :all, message: format(DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, max_size), report_type: :warning)
      size = case type
             when :insertions
               insertions_size(file_selector: file_selector, line_selector: line_selector)
             when :deletions
               deletions_size(file_selector: file_selector, line_selector: line_selector)
             when :all
               diff_size(file_selector: file_selector, line_selector: line_selector)
             else
               raise ArgumentError, "Unknown diff size type: #{type.inspect}. Use :insertions, :deletions, or :all."
             end

      reporter.report(message: message, type: report_type) if size > max_size
    end

    # Check the size of the Pull Request description (PR body) against a specified minimum size.
    #
    # @param min_length [Integer] The minimum allowed length for the PR body.
    # @param message [String] The message to display if the length of the PR body is smaller than the minimum. (default: DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT)
    # @param report_type [Boolean] If true, fail the PR check when the PR body length is too small. (default: false)
    #
    # @return [void]
    def check_pr_body(min_length:, message: format(DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, min_length), report_type: :warning)
      return if danger.github.pr_body.length > min_length

      reporter.report(message: message, type: report_type)
    end

    # Calculate the total size of insertions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the insertions calculation.
    # @param line_selector [Proc] Optional closure to select which added lines are counted (see #check_diff_size).
    #
    # @return [Integer] The total size of insertions in the selected modified files.
    def insertions_size(file_selector: nil, line_selector: nil)
      return filtered_diff_size(file_selector: file_selector, line_selector: line_selector, change_types: [:added]) if line_selector

      return danger.git.insertions unless file_selector

      # Only check added and modified files - deleted files have 0 insertions
      filtered_files = git_utils.added_and_modified_files.select(&file_selector)

      filtered_files.sum do |file|
        # Use cached stats directly instead of calling info_for_file for each file
        danger.git.diff.stats[:files][file]&.[](:insertions).to_i
      end
    end

    # Calculate the total size of deletions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the deletions calculation.
    # @param line_selector [Proc] Optional closure to select which removed lines are counted (see #check_diff_size).
    #
    # @return [Integer] The total size of deletions in the selected modified files.
    def deletions_size(file_selector: nil, line_selector: nil)
      return filtered_diff_size(file_selector: file_selector, line_selector: line_selector, change_types: [:removed]) if line_selector

      return danger.git.deletions unless file_selector

      filtered_files = git_utils.all_changed_files.select(&file_selector)

      filtered_files.sum do |file|
        # Use cached stats directly instead of calling info_for_file for each file
        danger.git.diff.stats[:files][file]&.[](:deletions).to_i
      end
    end

    # Calculate the total size of changes (insertions and deletions) in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the total insertions and deletions calculation.
    # @param line_selector [Proc] Optional closure to select which added/removed lines are counted (see #check_diff_size).
    #
    # @return [Integer] The total size of changes in the selected modified files.
    def diff_size(file_selector: nil, line_selector: nil)
      return filtered_diff_size(file_selector: file_selector, line_selector: line_selector, change_types: %i[added removed]) if line_selector

      return danger.git.lines_of_code unless file_selector

      filtered_files = git_utils.all_changed_files.select(&file_selector)

      filtered_files.sum do |file|
        # Use cached stats directly instead of calling info_for_file for each file
        stats = danger.git.diff.stats[:files][file]
        next 0 unless stats

        stats[:deletions].to_i + stats[:insertions].to_i
      end
    end

    private

    # Count the changed lines across the selected files by iterating the diff patches, keeping only the lines
    # whose change type is included in `change_types` and for which `line_selector` returns true.
    #
    # This is slower than the cached-numstats path used when no `line_selector` is given, since it needs the
    # actual patch content to evaluate each line, but it is the only way to exclude specific lines (e.g. comments).
    #
    # @param file_selector [Proc, nil] Optional closure to select the files to inspect.
    # @param line_selector [Proc] Closure receiving a changed line's content (without the `+`/`-` marker),
    #   returning true when the line should be counted.
    # @param change_types [Array<Symbol>] The diff change types to count (any of :added, :removed).
    #
    # @return [Integer] The total number of counted changed lines.
    def filtered_diff_size(file_selector:, line_selector:, change_types:)
      files = git_utils.all_changed_files
      files = files.select(&file_selector) if file_selector

      files.sum do |file|
        # `patch` can be nil (e.g. binary files), in which case there are no textual lines to count.
        patch = danger.git.diff_for_file(file)&.patch
        next 0 unless patch

        patch.each_line.count do |diff_line|
          next false unless change_types.include?(git_utils.change_type(diff_line: diff_line))

          line_selector.call(strip_diff_marker(diff_line))
        end
      end
    end

    # Strip the leading `+`/`-` diff marker and the trailing newline from a diff patch line,
    # so that `line_selector` only sees the actual line content.
    #
    # @param diff_line [String] A line from a diff patch, e.g. `"+    // a comment\n"`.
    #
    # @return [String] The line content, e.g. `"    // a comment"`.
    def strip_diff_marker(diff_line)
      without_marker = diff_line[1..].to_s
      without_marker.chomp
    end
  end
end
