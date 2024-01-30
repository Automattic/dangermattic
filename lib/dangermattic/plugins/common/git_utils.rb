# frozen_string_literal: true

module Danger
  # Represents a utility plugin for working with Git: to check added and modified lines in Git diffs,
  # to determine the type of change (added, removed, or other) in a diff line, and to retrieve lists of
  # added, modified, and deleted files.
  #
  # @example Check if there is a "TODO" in Ruby files:
  #          git_utils.check_added_diff_lines(
  #            file_selector: ->(path) { path.end_with?('.rb') },
  #            line_matcher: ->(line) { line.include?('TODO') },
  #            message: 'Found a TODO in a Ruby file'
  #          )
  #
  # @example Get added lines from a diff patch:
  #          added_lines = git_utils.added_lines(diff_patch: diff_patch)
  #
  # @example Get removed lines from a diff patch:
  #          removed_lines = git_utils.removed_lines(diff_patch: diff_patch)
  #
  # @example Determining the change type of a diff line:
  #          git_utils.change_type(diff_line: "+ new line added")
  #          #=> :added
  #
  #         git_utils.change_type(diff_line: "- line removed")
  #         #=> :removed
  #
  #         git_utils.change_type(diff_line: " context line")
  #         #=> :other
  #
  # @example Select removed lines from a diff patch:
  #          removed_lines = git_utils.select_lines(diff_patch: diff_patch, change_type: :removed)
  #
  # @see Automattic/dangermattic
  # @tags tool, util, git
  #
  class GitUtils < Plugin
    # Check added lines in a PR for a specific pattern and issue a warning or failure message when found.
    #
    # @param file_selector [Proc] A block to select the files in the PR.
    #   The block should take a file path as input and return true if the file should be checked.
    #
    # @param line_matcher [Proc] A block that will select the diff lines to report.
    #   The block should take a line of text as input and return true if the line matches the pattern.
    #
    # @param message [String] The warning or failure message to display when the pattern is found in a line.
    #
    # @param report_type [Boolean] (optional) When set to true, whenever a line matches the criteria, the method will emit an error, when false, emit a warning. Default is false.
    #
    # @example Checking for added lines containing 'FIXME' and failing the build:
    #   check_added_diff_lines(file_selector: ->(path) { File.extname(path) == ('.swift') }, line_matcher: ->(line) { line.include?("FIXME") }, message: "A FIXME was added, failing build.", report_type: :error)
    #
    # @return [void]
    def check_added_diff_lines(file_selector:, line_matcher:, message:, report_type: :warning)
      modified_files = added_and_modified_files.select(&file_selector)

      matches = matching_lines_in_diff_files(
        files: modified_files,
        line_matcher: line_matcher,
        change_type: :added
      )

      matches.each do |match|
        match.lines.each do |line|
          final_message = <<~MESSAGE
            #{message}
            File `#{match.file}`:
            ```diff
            #{line.chomp}
            ```
          MESSAGE

          reporter.report(message: final_message, type: report_type)
        end
      end
    end

    MatchedData = Struct.new(:file, :lines)

    # Matches diff lines in the provided files based on the line matcher and change type
    #
    # @param files [Array<String>] List of file names to check
    # @param line_matcher [Proc] A callable that takes a line and returns true if it matches the desired pattern
    # @param change_type [Symbol, nil] Change type to filter lines (e.g., :added, :removed) or nil for no filter
    # @return [Array<MatchedData>] Array of MatchedData objects representing matched lines in files
    def matching_lines_in_diff_files(files:, line_matcher:, change_type: nil)
      matched_data = []

      files.each do |file|
        matched_lines = []

        diff = danger.git.diff_for_file(file)

        diff.patch.each_line do |line|
          matched_lines << line if line_matcher.call(line) && (change_type.nil? || change_type(diff_line: line) == change_type)
        end

        matched_data << MatchedData.new(file, matched_lines) unless matched_lines.empty?
      end

      matched_data
    end

    # Determine the type of change for a given line in a git diff.
    #
    # @param diff_line [String] The line from a git diff that needs to be classified.
    #
    # @return [Symbol] The type of change for the given diff line. Possible values are:
    #   - :added for added lines
    #   - :removed for removed lines
    #   - :other for any other type of lines
    def change_type(diff_line:)
      if diff_line.start_with?('+') && !diff_line.start_with?('+++ ')
        :added
      elsif diff_line.start_with?('-') && !diff_line.start_with?('--- ')
        :removed
      else
        :other
      end
    end

    # Get the list of added and modified files in the current Pull Request.
    #
    # @return [Array<String>] An array containing the file paths of added and modified files.
    def added_and_modified_files
      danger.git.added_files + danger.git.modified_files
    end

    # Get the list of all files added, modified and deleted in the current Pull Request.
    #
    # @return [Array<String>] An array containing the file paths of all changed files.
    #
    def all_changed_files
      danger.git.added_files + danger.git.modified_files + danger.git.deleted_files
    end

    # Returns the lines that were added in the given diff patch.
    #
    # @param diff_patch [String] The diff patch containing the changes.
    #
    # @return [String] A concatenated string of added lines.
    def added_lines(diff_patch:)
      select_lines(diff_patch: diff_patch, change_type: :added)
    end

    # Returns the lines that were removed in the given diff patch.
    #
    # @param diff_patch [String] The diff patch containing the changes.
    #
    # @return [String] A concatenated string of removed lines.
    def removed_lines(diff_patch:)
      select_lines(diff_patch: diff_patch, change_type: :removed)
    end

    # Selects lines of a specific change type (added or removed) from the given diff patch.
    #
    # @param diff_patch [String] The diff patch containing the changes.
    # @param change_type [Symbol] The desired change type (:added or :removed).
    #
    # @return [String] A concatenated string of selected lines of the specified change type.
    def select_lines(diff_patch:, change_type:)
      selected_lines = diff_patch.lines.select { |line| change_type(diff_line: line) == change_type }
      selected_lines.map { |line| line[1..] }.join
    end
  end
end
