# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidUnitTestChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_unit_test_checker

        allow(@plugin.github).to receive(:pr_labels).and_return(['my_label'])

        stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
      end

      it 'reports the right errors when a PR adds new classes that do not have corresponding tests' do
        added_files = %w[
          src/main/java/org/wordpress/util/config/BloggingPromptsFeatureConfig.kt
          Abc.java
          src/androidTest/java/org/test/ToolTest.kt
          Polygon.kt
          Abcdef.kt
          TestsINeedThem.java
          TestsINeedThem2.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)

        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        classes = %w[
          BloggingPromptsFeatureConfig
          Abc
          Polygon
          Abcdef
          TestsINeedThem
          TestsINeedThem2
          TestsINeedThem2AnotherClass
        ]

        expect_class_names_match_report(class_names: classes, error_report: @dangerfile.status_report[:errors])
      end

      it 'does not report errors when new classes have corresponding tests' do
        added_files = %w[
          Abc.java
          src/androidTest/java/org/test/AbcTests.java
          Polygon.kt
          src/androidTest/java/org/test/PolygonTest.kt
          TestsINeedThem.java
          src/androidTest/java/org/test/AnotherTestClass.java
          MyNewClass.java
          src/androidTest/java/org/test/TestMyNewClass.java
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end

      it 'does not report errors when we are deleting classes' do
        deleted_files = %w[
          Abc.java
          Polygon.kt
          TestsINeedThem.java
        ]

        diff = generate_delete_diff_from_fixtures(deleted_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end

      it 'reports errors when we remove test classes for classes we refactored' do
        added_files = %w[
          Abc.java
          Polygon.kt
          TestsINeedThem.kt
        ]

        removed_files = %w[
          src/androidTest/java/org/test/AbcTests.java
          src/androidTest/java/org/test/PolygonTest.kt
          src/test/java/org/test/TestsINeedThem.java
        ]

        diff = generate_add_diff_from_fixtures(added_files) + generate_delete_diff_from_fixtures(removed_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        classes = %w[
          Abc
          Polygon
          TestsINeedThem
        ]

        expect_class_names_match_report(class_names: classes, error_report: @dangerfile.status_report[:errors])
      end

      it 'does nothing when a PR adds only tests' do
        added_files = %w[
          src/androidTest/java/org/test/AbcTests.java
          src/androidTest/java/org/test/PolygonTest.kt
          src/test/java/org/test/TestsINeedThem.java
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR adds classes that dont need tests' do
        added_files = %w[
          src/android/java/org/activities/MyActivity.kt
          src/android/java/org/activities/MyJavaActivity.java
          src/android/java/org/fragments/MyFragment.kt
          src/android/java/org/fragments/MyNewJavaFragment.java
          src/android/java/org/module/MyModule.java
          src/android/java/org/view/MyRecyclerView.java
          src/android/java/org/view/ActionCardViewHolder.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end

      it 'ensures data classes with no {…} body don\'t mess up detection of subsequent classes in the same file' do
        # Ensure the CLASS_MODIFIER_DETECTOR regex doesn't assume class declaration always ends with `{` marking the class body
        # (which would lead the regex to either miss the data class or extend the regex to the next `{`… that potentially belongs to the next class)
        # This is especially important given data classes might not have a body at all

        mix_data_plus_normal_class_file = 'MixDataPlusNormalClass.kt'
        data_and_normal_class_diff = generate_add_diff_from_fixtures([mix_data_plus_normal_class_file])

        allow(@dangerfile.git).to receive(:diff).and_return(data_and_normal_class_diff)

        @plugin.check_missing_tests

        expect_class_names_match_report(class_names: ['DummyClassMissingTest'], error_report: @dangerfile.status_report[:errors])
      end

      context 'when detecting classes and class modifiers' do
        let(:added_files) do
          dayone_source_fixtures_subdir = %w[src main java com dayoneapp dayone]
          Dir.glob('**/*.kt', base: fixture_path('android_unit_test_checker', dayone_source_fixtures_subdir))
             .map { |file| File.join(dayone_source_fixtures_subdir, file) }
        end
        let(:diff) { generate_add_diff_from_fixtures(added_files) }

        # ClassName => Expected to be detected (true) or ignored (false)
        let(:expected_detected_classes) do
          {
            # ApiResult.kt
            'ApiResult' => false,   # `sealed class ApiResult<T>`
            'Success' => false,     # `data class Success<T>`
            'Empty' => false,       # `class Empty<T> : ApiResult<T>()` (but no body)
            'Failure' => false,     # `data class Failure<T>(…)`
            'FailureType' => false, # `enum class FailureType`

            # WebRecordApi.kt
            'CursorTime' => false,       # `value class CursorTime`
            'WebRecordChanges' => false, # `data class WebRecordChanges`

            # UiStates.kt
            'LoadKeyUiState' => false, # `sealed class LoadKeyUiState`

            # AppIntegrationModule.kt
            'AppIntegrationHandlers' => false, # `annotation class AppIntegrationHandlers`

            # StreaksViewModel.kt
            'StreaksViewModel' => true,     # `class StreaksViewModel`
            'Streaks' => false,             # `data class Streaks`
            'JournalOptionsState' => false, # `class JournalOptionsState` (but no body)
            'StreakWeekDay' => false,       # `data class StreakWeekDay`
            'DayJournaled' => false,        # `value class DayJournaled`
            'StreakJournal' => false,       # `data class StreakJournal`
            'DaysOfWeekList' => false,      # `private class DaysOfWeekList`
            'PreviousDays' => false,        # `class PreviousDays` (but no body)

            # MediaStorageConfiguration.kt
            'CompressQuality' => false,           # `value class CompressQuality`
            'MediaStorageConfiguration' => false, # `class MediaStorageConfiguration` (but no body)
            'ThumbnailsConfiguration' => false,   # `class ThumbnailsConfiguration` (but no body)

            # AccountType.kt
            'AccountType' => false, # `enum class AccountType`

            # SelectPhotoUseCase.kt
            'SelectPhotoUseCase' => true, # `class SelectPhotoUseCase`
            'GetMultipleImages' => false, # `private class GetMultipleImages`
            'GetSingleImage' => false # `private class GetSingleImage`
          }
        end

        before do
          allow(@dangerfile.git).to receive(:diff).and_return(diff)
        end

        it 'reports only classes that don\'t have a modifier that is part of modifier exceptions' do
          @plugin.check_missing_tests
          expected_violating_classes = expected_detected_classes.filter_map { |k, v| k if v } # only keys whose value is true
          expect_class_names_match_report(class_names: expected_violating_classes, error_report: @dangerfile.status_report[:errors])
        end

        it 'validates that the RegEx matches all classes from source code' do
          # Mock detection of exceptions in order to make `check_missing_tests` report all classes regardless of modifiers
          # This allows us to validate that our RegEx matches all classes from the source code in the first place
          allow(@plugin).to receive(:class_match_is_exception?).and_return(false)
          @plugin.check_missing_tests
          expect_class_names_match_report(class_names: expected_detected_classes.keys, error_report: @dangerfile.status_report[:errors])
        end
      end

      it 'does not report that a PR with the tests bypass label is missing tests' do
        added_files = %w[
          Abc.java
          Abcdef.kt
          TestsINeedThem2.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return(['unit-tests-exemption'])

        @plugin.check_missing_tests

        expected_warnings = [
          'Class `Abc` is missing tests, but `unit-tests-exemption` label was set to ignore this.',
          'Class `Abcdef` is missing tests, but `unit-tests-exemption` label was set to ignore this.',
          'Class `TestsINeedThem2` is missing tests, but `unit-tests-exemption` label was set to ignore this.',
          'Class `TestsINeedThem2AnotherClass` is missing tests, but `unit-tests-exemption` label was set to ignore this.'
        ]
        expect(@dangerfile).to report_warnings(expected_warnings)
      end

      it 'does not report errors when a PR without tests with a custom bypass label is missing tests' do
        added_files = %w[
          Abc.java
          src/androidTest/java/org/test/AnotherTestClass.java
          Abcdef.kt
        ]

        ignore_label = 'ignore-no-tests'

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return([ignore_label])

        @plugin.check_missing_tests(bypass_label: ignore_label)

        expected_warnings = [
          'Class `Abc` is missing tests, but `ignore-no-tests` label was set to ignore this.',
          'Class `Abcdef` is missing tests, but `ignore-no-tests` label was set to ignore this.'
        ]
        expect(@dangerfile).to report_warnings(expected_warnings)
      end

      it 'does not report that added classes that need tests but with custom classes exception patterns are missing tests' do
        added_files = %w[
          src/androidTest/java/org/test/ToolTest.kt
          AnotherViewHelper.kt
          AbcdefgViewHelper.java
          TestsINeedThem.java
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        classes_to_ignore = [
          /ViewHelper$/
        ].freeze

        @plugin.check_missing_tests(classes_exceptions: classes_to_ignore)

        classes = ['TestsINeedThem']
        expect_class_names_match_report(class_names: classes, error_report: @dangerfile.status_report[:errors])
      end

      it 'does not report that added classes that need tests but with custom subclasses exception patterns are missing tests' do
        added_files = %w[
          AbcFeatureConfig.java
          src/main/java/org/wordpress/android/widgets/NestedWebView.kt
          src/androidTest/java/org/test/AnotherTestClass.java
          src/main/java/org/wordpress/util/config/BloggingPromptsFeatureConfig.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        subclasses_to_ignore = [
          /FeatureConfig$/
        ].freeze

        @plugin.check_missing_tests(subclasses_exceptions: subclasses_to_ignore)

        classes = ['NestedWebView']
        expect_class_names_match_report(class_names: classes, error_report: @dangerfile.status_report[:errors])
      end

      it 'does not report that added classes with a path filter are missing tests' do
        added_files = %w[
          AbcFeatureConfig.java
          AnotherViewHelper.kt
          src/main/java/org/wordpress/util/config/BloggingPromptsFeatureConfig.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        path_exceptions = ['src/main/java/org/wordpress/**', '*.java']

        @plugin.check_missing_tests(path_exceptions: path_exceptions)

        classes = ['AnotherViewHelper']
        expect_class_names_match_report(class_names: classes, error_report: @dangerfile.status_report[:errors])
      end

      it 'does nothing when a PR moves code around with both additions and removals in the diff' do
        shape_file = 'Shape.kt'

        polygon_test_diff_str = <<~PATCH
          diff --git a/PolygonTest.kt b/PolygonTest.kt
          index 8c2bed6..ae81c49 100644
          --- a/PolygonTest.kt
          +++ b/PolygonTest.kt
          @@ -1,8 +1,9 @@
          -class PolygonTest {
          -  val sut10: Shape = Polygon(sides = 10)
          -  val sut5: Shape = Polygon(sides = 5)
          -
          -  fun testDraw() {
          -    Polygon(sides = 5).draw()
          +class ShapesTest {
          +  fun testPentagon() {
          +    draw(Polygon(sides = 5))
          +  }
          +
          +  private fun draw(shape: Shape) {
          +    shape.draw()
            }
          }
        PATCH

        shape_diff = generate_add_diff_from_fixtures([shape_file])
        polygon_diff = GitDiffStruct.new('modified', 'project/src/androidTest/java/shapes/PolygonTest.kt', polygon_test_diff_str)

        allow(@dangerfile.git).to receive(:diff).and_return(shape_diff + [polygon_diff])

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end

      it 'does not report private class' do
        added_files = %w[
          PublicAndPrivateType.kt
          src/androidTest/java/org/test/PublicTypeTest.kt
        ]

        diff = generate_add_diff_from_fixtures(added_files)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile).to not_report
      end
    end

    def generate_add_diff_from_fixtures(paths)
      paths.map do |path|
        content = fixture('android_unit_test_checker', path)
        diff_str = generate_add_diff(file_path: path, content: content)

        GitDiffStruct.new('new', path, diff_str)
      end
    end

    def generate_delete_diff_from_fixtures(paths)
      paths.map do |path|
        content = fixture('android_unit_test_checker', path)
        diff_str = generate_delete_diff(file_path: path, content: content)

        GitDiffStruct.new('deleted', path, diff_str)
      end
    end

    def generate_delete_diff(file_path:, content:)
      <<~PATCH
        diff --git a/#{file_path} b/#{file_path}
        deleted file mode 100644
        index fd48a22..0000000
        --- a/#{file_path}
        +++ /dev/null
        @@ -1 +0,0 @@
        #{prefix_text_lines(content: content, prefix: '-')}
        \\ No newline at end of file
      PATCH
    end

    def generate_add_diff(file_path:, content:)
      <<~PATCH
        diff --git a/#{file_path} b/#{file_path}
        new file mode 100644
        index 0000000..fd48a22
        --- /dev/null
        +++ b/#{file_path}
        @@ -0,0 +1 @@
        #{prefix_text_lines(content: content, prefix: '+')}
        \\ No newline at end of file
      PATCH
    end

    def prefix_text_lines(content:, prefix:)
      content.lines.map { |line| "#{prefix}#{line.chomp}" }.join("\n")
    end

    def expect_class_names_match_report(class_names:, error_report:)
      if error_report.length != class_names.length
        reported_class_names = error_report.map { |e| e.match(/class `(.*?)`/)[1] }
        expect(reported_class_names).to eq(class_names)
      end
      class_names.zip(error_report).each do |cls, error|
        expect(error).to include "Please add tests for class `#{cls}`"
      end
    end
  end
end
