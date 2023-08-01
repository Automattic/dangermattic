# frozen_string_literal: true

module Danger
  # Plugin to check the size of a Pull Request content and text body.
  class PRSizeChecker < Plugin
    DEFAULT_MAX_DIFF_SIZE = 500
    DEFAULT_DIFF_SIZE_MESSAGE = "This PR is larger than #{DEFAULT_MAX_DIFF_SIZE} lines of changes. Please consider splitting it into smaller PRs for easier and faster reviews.".freeze
    DEFAULT_MIN_PR_BODY = 10
    DEFAULT_MIN_PR_BODY_MESSAGE = "The PR description appears very short, less than #{DEFAULT_MIN_PR_BODY} characters long. Please provide a summary of your changes in the PR description.".freeze

    # Check the size of the PR diff against a specified maximum size.
    #
    # @param file_selector [Proc] Optional closure to filter the files in the diff to be used for size calculation.
    # @param type [:insertions, :deletions, :all] The type of diff size to check. (default: :all)
    # @param max_size [Integer] The maximum allowed size for the diff. (default: DEFAULT_MAX_DIFF_SIZE)
    # @param message [String] The message to display if the diff size exceeds the maximum. (default: DEFAULT_DIFF_SIZE_MESSAGE)
    # @param fail_on_error [Boolean] If true, fail the PR check when the diff size exceeds the maximum (default: false).
    def check_diff_size(file_selector: nil, type: :all, max_size: DEFAULT_MAX_DIFF_SIZE, message: DEFAULT_DIFF_SIZE_MESSAGE, fail_on_error: false)
      case type
      when :insertions
        if insertions_size(file_selector: file_selector) > max_size
          fail_on_error ? failure(message) : warn(message)
        end
      when :deletions
        if deletions_size(file_selector: file_selector) > max_size
          fail_on_error ? failure(message) : warn(message)
        end
      when :all
        if diff_size(file_selector: file_selector) > max_size
          fail_on_error ? failure(message) : warn(message)
        end
      end
    end

    # Check the size of the Pull Request description (PR body) against a specified minimum size.
    #
    # @param min_length [Integer] The minimum allowed length for the PR body. (default: DEFAULT_MIN_PR_BODY)
    # @param fail_on_error [Boolean] If true, fail the PR check when the PR body length is too small. (default: false)
    def check_pr_body(min_length: DEFAULT_MIN_PR_BODY, message: DEFAULT_MIN_PR_BODY_MESSAGE, fail_on_error: false)
      return if danger.github.pr_body.length > min_length

      fail_on_error ? failure(message) : warn(message)
    end

    # Calculate the total size of insertions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the insertions calculation.
    # @return [Integer] The total size of insertions in the selected modified files.
    def insertions_size(file_selector:)
      return danger.git.insertions unless file_selector

      filtered_files = all_modified_files.select(&file_selector)
      filtered_files.sum { |file| danger.git.info_for_file(file)[:insertions].to_i }
    end

    # Calculate the total size of deletions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the deletions calculation.
    # @return [Integer] The total size of deletions in the selected modified files.
    def deletions_size(file_selector:)
      return danger.git.deletions unless file_selector

      filtered_files = all_modified_files.select(&file_selector)
      filtered_files.sum { |file| danger.git.info_for_file(file)[:deletions].to_i }
    end

    # Calculate the total size of changes (insertions and deletions) in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the total insertions and deletions calculation.
    # @return [Integer] The total size of changes in the selected modified files.
    def diff_size(file_selector:)
      return danger.git.lines_of_code unless file_selector

      filtered_files = all_modified_files.select(&file_selector)
      filtered_files.sum { |file| danger.git.info_for_file(file)[:deletions].to_i + danger.git.info_for_file(file)[:insertions].to_i }
    end

    private

    def all_modified_files
      danger.git.added_files + danger.git.modified_files + danger.git.deleted_files
    end
  end
end
