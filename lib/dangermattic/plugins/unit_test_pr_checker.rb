# frozen_string_literal: true

require_relative 'utils/git_utils'

module Danger
  # Plugin to detect classes without Unit Tests in a PR.
  class UnitTestPRChecker < Plugin
    ANY_CLASS_DETECTOR = /class ([A-Z]\w+)\s*(.*?)\s*{/.freeze
    NON_PRIVATE_CLASS_DETECTOR = /(?:\s|public|internal|protected|final|abstract|static)*class ([A-Z]\w+)\s*(.*?)\s*{/.freeze

    CLASSES_EXCEPTIONS = [
      /ViewHolder$/,
      /Module$/,
      /ViewController$/
    ].freeze

    SUBCLASSES_EXCEPTIONS = [
      /(Fragment|Activity)\b/,
      /RecyclerView/
    ].freeze

    UNIT_TESTS_BYPASS_PR_LABEL = 'unit-tests-exemption'

    attr_accessor :classes_exceptions, :subclasses_exceptions

    # Check and warns about missing unit tests for a Git diff, with optional classes/subclasses to ignore and an optional PR label to bypass the checks.
    #
    # @param classes_exceptions [Array<String>] Optional list of regexes matching class names to exclude from the check.
    #   Defaults to CLASSES_EXCEPTIONS.
    # @param subclasses_exceptions [Array<String>] Optional list of regexes matching base class names to exclude from the check.
    #   Defaults to SUBCLASSES_EXCEPTIONS.
    # @param bypass_label [String] Optional label to indicate we can bypass the check. Defaults to
    #   UNIT_TESTS_BYPASS_PR_LABEL.
    # @return [void]
    #
    # @example Check missing unit tests
    #   check_missing_tests()
    #
    # @example Check missing unit tests excluding certain classes and subclasses
    #   check_missing_tests(classes_exceptions: [/ViewHolder$/], subclasses_exceptions: [/RecyclerView/])
    #
    # @example Check missing unit tests with a custom bypass label
    #   check_missing_tests(bypass_label: 'BypassTestCheck')
    def check_missing_tests(classes_exceptions: CLASSES_EXCEPTIONS, subclasses_exceptions: SUBCLASSES_EXCEPTIONS,
                            bypass_label: UNIT_TESTS_BYPASS_PR_LABEL)
      @classes_exceptions = classes_exceptions
      @subclasses_exceptions = subclasses_exceptions

      list = find_classes_missing_tests(git_diff: git.diff)

      return if list.empty?

      if danger.github.pr_labels.include?(bypass_label)
        list.each do |c|
          warn("Class `#{c.classname}` is missing tests, but `#{bypass_label}` label was set to ignore this.")
        end
      else
        list.each do |c|
          failure("Please add tests for class `#{c.classname}` (or add `#{bypass_label}` label to ignore this).")
        end
      end
    end

    private

    ClassViolation = Struct.new(:classname, :file)

    # @param [Git::Diff] git_diff the object
    # @return [Array<ClassViolation>] An array of `ClassViolation` objects for each added class that is missing a test
    def find_classes_missing_tests(git_diff:)
      violations = []
      removed_classes = []
      added_test_lines = []

      # Parse the diff of each file, storing test lines for test files, and added/removed classes for non-test files
      git_diff.each do |file_diff|
        path = file_diff.path
        if test_file?(path: path)
          # Store added test lines from test files
          added_test_lines += file_diff.patch.each_line.select do |line|
            GitUtils.change_type(diff_line: line) == :added
          end
        else
          # Detect added and removed classes in non-test files
          file_diff.patch.each_line do |line|
            case GitUtils.change_type(diff_line: line)
            when :added
              matches = line.scan(NON_PRIVATE_CLASS_DETECTOR)
              matches.reject! { |m| class_match_is_exception?(match: m, file: path) }
              violations += matches.map { |m| ClassViolation.new(m[0], path) }
            when :removed
              matches = line.scan(ANY_CLASS_DETECTOR)
              removed_classes += matches.map { |m| m[0] }
            end
          end
        end
      end

      # We only want newly added classes, not if class signature was modified or line was moved
      violations.reject! { |v| removed_classes.include?(v.classname) }
      # For each remaining candidate, only keep the ones _not_ used in a new test
      violations.select { |v| added_test_lines.none? { |line| line =~ /\b#{v.classname}\b/ } }
    end

    # @param [Array<String>] match an array of captured substrings matching our `*_CLASS_DETECTOR` for a given line
    # @param [String] file the path to the file where that class declaration line was matched
    def class_match_is_exception?(match:, file:)
      return true if @classes_exceptions.any? { |re| match[0] =~ re }

      subclass_regexp = File.extname(file) == '.java' ? /extends ([A-Z]\w+)/ : /\s*:\s*([A-Z]\w+)/
      subclass = match[1].match(subclass_regexp)&.captures&.first
      @subclasses_exceptions.any? { |re| subclass =~ re }
    end

    def test_file?(path:)
      GitUtils.android_test_file?(path: path) || GitUtils.ios_test_file?(path: path)
    end
  end
end
