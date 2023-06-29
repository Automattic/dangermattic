# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::UnitTestPRChecker do
    it 'should be a plugin' do
      expect(Danger::UnitTestPRChecker.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.unit_test_pr_checker

        allow(@my_plugin.github).to receive(:pr_labels).and_return(['my_label'])
      end

      it 'shows that an Android PR needs tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)

          @my_plugin.check_missing_tests

          expect(@dangerfile.status_report[:errors].count).to eq 2
        end
      end

      it 'shows that an iOS PR needs tests' do
        changes_dict = {
          'Helper.swift' => 'final class Helper { help() { print(''); } }',
          'MyFolderTests/ATest.swift' => 'class ATest: XCTestCase { testMore() {} }',
          'AnotherHelper.swift' => 'class AnotherHelper<A> { helpAgain() { print(''); } }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)

          @my_plugin.check_missing_tests

          expect(@dangerfile.status_report[:errors].count).to eq 2
        end
      end

      it 'does nothing when an Android PR have only tests' do
        changes_dict = {
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'project/src/androidTest/java/org/test/UtilsTest.kt' => 'class UtilsTest { void testMe() {} }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)

          @my_plugin.check_missing_tests

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end

      it 'does nothing when an iOS PR have only tests' do
        changes_dict = {
          'MyFolderTests/ATest.swift' => 'class ATest: XCTestCase { testA() {} }',
          'MyFolderTests/SomeMoreTests.swift' => 'class SomeMoreTests: XCTestCase { testMore() {} }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)

          @my_plugin.check_missing_tests

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end

      it 'does not show that a PR with a tests bypass label is missing tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)
          allow(@my_plugin.github).to receive(:pr_labels).and_return(['unit-tests-exemption'])

          @my_plugin.check_missing_tests

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end

      it 'does not show that a PR with a custom bypass label is missing tests' do
        changes_dict = {
          'File1.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(''); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'File2.kt' => 'class Abcdef(name: String) { public void testMe() { println(''); } }'
        }

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          bypass_label = 'ignore-no-tests'

          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)
          allow(@my_plugin.github).to receive(:pr_labels).and_return([bypass_label])

          @my_plugin.check_missing_tests(bypass_label: bypass_label)

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
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

        run_in_repo_with_diff(changes_dict: changes_dict) do |git|
          allow(@dangerfile.git).to receive(:diff).and_return(git.diff)

          @my_plugin.check_missing_tests(classes_exceptions: exceptions, subclasses_exceptions: subclasses_exceptions)

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end
    end

    def run_in_repo_with_diff(changes_dict:)
      Dir.mktmpdir do |dir|
        Dir.chdir dir do
          `git init -b master`

          changes_dict.each do |key, _value|
            file_path = "#{dir}/#{key}"
            FileUtils.mkdir_p(File.dirname(file_path))
            File.open(file_path, 'w') { |f| f.write "Initial #{key} content." }
          end

          `git add .`
          `git commit -m "add files"`

          # adds changes to the previously commited files to create a diff
          changes_dict.each do |key, value|
            File.open("#{dir}/#{key}", 'w') { |f| f.write(value) }
          end

          g = Git.open('.')
          yield g
        end
      end
    end
  end
end
