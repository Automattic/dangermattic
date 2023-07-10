# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidUnitTestPRChecker do
    it 'should be a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_unit_test_pr_checker

        allow(@plugin.github).to receive(:pr_labels).and_return(['my_label'])
      end

      it 'shows that a PR needs tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        diff = generate_changes_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors].count).to eq 2
      end

      it 'does nothing when a PR has only tests' do
        changes_dict = {
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'project/src/androidTest/java/org/test/UtilsTest.kt' => 'class UtilsTest { void testMe() {} }'
        }

        diff = generate_changes_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show that a PR with a tests bypass label is missing tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        diff = generate_changes_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return(['unit-tests-exemption'])

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show that a PR with a custom bypass label is missing tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        bypass_label = 'ignore-no-tests'

        diff = generate_changes_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return([bypass_label])

        @plugin.check_missing_tests(bypass_label: bypass_label)

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show that a PR with custom classes / subclasses patterns are missing tests' do
        exceptions = [
          /ViewHelper$/
        ].freeze

        subclasses_exceptions = [
          /BaseViewWrangler/
        ].freeze

        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc extends BaseViewWrangler { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class AbcdefViewHelper(name: String) { public void testMe() { println(''); } }'
        }

        diff = generate_changes_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests(classes_exceptions: exceptions, subclasses_exceptions: subclasses_exceptions)

        expect(@dangerfile.status_report[:errors]).to be_empty
      end
    end

    def generate_changes_diff(changes_dict)
      diff_lines = changes_dict.map do |file_path, content|
        diff_str = <<~PATCH
        diff --git a/#{file_path} b/#{file_path}
        index 790344f..fd48a22 100644
        --- a/#{file_path}
        +++ b/#{file_path}
        @@ -1 +1 @@
        -Initial #{file_path} content.
        \\ No newline at end of file
        +#{content}
        \\ No newline at end of file
        PATCH

        OpenStruct.new(type: 'modified', path: file_path, patch: diff_str)
      end
    end
  end
end
