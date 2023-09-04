# frozen_string_literal: true

require_relative 'utils/git_utils'

module Danger
  # This plugin provides methods to check for the presence of unit tests for newly added classes in a pull request.
  #
  # @example Check missing unit tests using the default parameters:
  #          android_unit_test_checker.check_missing_tests
  #
  # @example Check missing unit tests while excluding certain classes, subclasses, and paths:
  #          android_unit_test_checker.check_missing_tests(
  #            classes_exceptions: [/ViewHolder$/],
  #            subclasses_exceptions: [/RecyclerView/],
  #            path_exceptions: ['*.java', 'org/app/ui/**']
  #          )
  #
  # @example Check missing unit tests with a custom bypass label:
  #          android_unit_test_checker.check_missing_tests(bypass_label: 'BypassTestCheck')
  #
  # @example Check missing unit tests excluding certain classes, subclasses and paths:
  #          android_unit_test_checker.check_missing_tests(classes_exceptions: [/ViewHolder$/], subclasses_exceptions: [/RecyclerView/], path_exceptions: ['*.java', 'org/app/ui/**'])
  #
  # @see Automattic/dangermattic
  # @tags android, unit test, github, pull request
  #
  class AndroidUnitTestChecker < Plugin
    ANY_CLASS_DETECTOR = /class\s+([A-Z]\w+)\s*(.*?)\s*{/m
    NON_PRIVATE_CLASS_DETECTOR = /(?:\s|public|internal|protected|final|abstract|static)*class\s+([A-Z]\w+)\s*(.*?)\s*{/m
    DEFAULT_CLASSES_EXCEPTIONS = [
      /ViewHolder$/,
      /Module$/,
      /Button$/
    ].freeze

    DEFAULT_SUBCLASSES_EXCEPTIONS = [
      /(Fragment|Activity)\b/,
      /RecyclerView/,
      /^BroadcastReceiver$/,
      /^ContentProvider$/,
      /Service$/,
      /View$/,
      /ViewGroup$/,
      /Layout$/
    ].freeze

    DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL = 'unit-tests-exemption'

    # Check and warns about missing unit tests for a Git diff, with optional classes/subclasses to ignore and an
    # optional PR label to bypass the checks.
    #
    # @param classes_exceptions [Array<String>] Optional list of regexes matching class names to exclude from the
    # check.
    #   Defaults to DEFAULT_CLASSES_EXCEPTIONS.
    # @param subclasses_exceptions [Array<String>] Optional list of regexes matching base class names to exclude from
    # the check.
    #   Defaults to DEFAULT_SUBCLASSES_EXCEPTIONS.
    # @param path_exceptions [Array<String>] Optional list of file paths to exclude from the check.
    #   Defaults to [].
    # @param bypass_label [String] Optional label to indicate we can bypass the check. Defaults to
    #   DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL.
    #
    # @return [void]
    def check_missing_tests(classes_exceptions: DEFAULT_CLASSES_EXCEPTIONS,
                            subclasses_exceptions: DEFAULT_SUBCLASSES_EXCEPTIONS,
                            path_exceptions: [],
                            bypass_label: DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL)
      list = find_classes_missing_tests(
        git_diff: git.diff,
        classes_exceptions: classes_exceptions,
        subclasses_exceptions: subclasses_exceptions,
        path_exceptions: path_exceptions
      )

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

    # @param git_diff [Git::Diff] the git diff object
    # @param classes_exceptions [Array<String>] Regexes matching class names to exclude from the check.
    # @param subclasses_exceptions [Array<String>] Regexes matching base class names to exclude from the check
    # @param path_exceptions [Array<String>] Regexes matching base class names to exclude from the check
    #
    # @return [Array<ClassViolation>] An array of `ClassViolation` objects for each added class that is missing a test
    def find_classes_missing_tests(git_diff:, classes_exceptions:, subclasses_exceptions:, path_exceptions:)
      violations = []
      removed_classes = []
      added_test_lines = []

      # Parse the diff of each file, storing test lines for test files, and added/removed classes for non-test files
      git_diff.each do |file_diff|
        file_path = file_diff.path

        next if path_exceptions.any? { |exception| File.fnmatch?(exception, file_path) }

        if test_file?(path: file_path)
          # Store added test lines from test files
          added_test_lines += file_diff.patch.each_line.select do |line|
            GitUtils.change_type(diff_line: line) == :added
          end
        else
          # Detect added classes (violations) and removed classes in non-test files
          patch = file_diff.patch

          violations += find_violations(
            path: file_path,
            diff_patch: patch,
            classes_exceptions: classes_exceptions,
            subclasses_exceptions: subclasses_exceptions
          )

          removed_classes += find_removed_classes(diff_patch: patch)
        end
      end

      # We only want newly added classes, not if class signature was modified or line was moved
      violations.reject! { |v| removed_classes.include?(v.classname) }

      # For each remaining candidate, only keep the ones _not_ used in a new test.
      # The regex will match usages of this class in any test file
      violations.select { |v| added_test_lines.none? { |line| line =~ /\b#{v.classname}\b/ } }
    end

    # Finds added classes that potentially will require a test (violations) in the given file based on the changes in the diff patch.
    #
    # @param path [String] The file in the diff to check for violations.
    # @param diff_patch [String] The diff patch containing the changes to the file.
    # @param classes_exceptions [Array<String>] An array of class names that are exceptions and should be ignored.
    # @param subclasses_exceptions [Array<String>] An array of class names whose subclasses should be ignored as well.
    #
    # @return [Array<ClassViolation>] An array of ClassViolation objects representing the violations found.
    def find_violations(path:, diff_patch:, classes_exceptions:, subclasses_exceptions:)
      added_lines = GitUtils.added_lines(diff_patch: diff_patch)
      matches = added_lines.scan(NON_PRIVATE_CLASS_DETECTOR)
      matches.reject! do |m|
        class_match_is_exception?(
          m,
          path,
          classes_exceptions,
          subclasses_exceptions
        )
      end

      matches.map { |m| ClassViolation.new(m[0], path) }
    end

    # Finds the names of removed classes based on the removals the diff patch.
    #
    # @param diff_patch [String] The diff patch containing the changes to the file.
    #
    # @return [Array<String>] An array with the class names of the classes that were removed in the diff.
    def find_removed_classes(diff_patch:)
      removed_lines = GitUtils.removed_lines(diff_patch: diff_patch)
      matches = removed_lines.scan(ANY_CLASS_DETECTOR)
      matches.map { |m| m[0] }
    end

    # @param match [Array<String>] match an array of captured substrings matching our `*_CLASS_DETECTOR` for a given line
    # @param file [String] file the path to the file where that class declaration line was matched
    # @param classes_exceptions [Array<String>] Regexes matching class names to exclude from the check.
    # @param subclasses_exceptions [Array<String>] Regexes matching base class names to exclude from the check
    #
    # @return [void]
    def class_match_is_exception?(match, file, classes_exceptions, subclasses_exceptions)
      return true if classes_exceptions.any? { |re| match[0] =~ re }

      subclass_regexp = File.extname(file) == '.java' ? /extends\s+([A-Z]\w+)/m : /\s*:\s*([A-Z]\w+)/m
      subclass = match[1].scan(subclass_regexp)&.last&.last
      subclasses_exceptions.any? { |re| subclass =~ re }
    end

    def test_file?(path:)
      path.match? %r{/(test|androidTest).*\.(java|kt)$}
    end
  end
end
