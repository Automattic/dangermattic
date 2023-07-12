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

      it 'shows the right number of errors when a PR adding new classes that do not have corresponding tests' do
        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { fun testMethod() {} }',
          'Polygon.kt' => 'abstract class Polygon { abstract fun draw() }',
          'Abcdef.kt' => 'class Abcdef(name: String) { fun testMe() { println("") } }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void testMe() { System.out.println(""); } }',
          'TestsINeedThem2.kt' => 'public open class TestsINeedThem2 { fun testMe2() { } }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        classes = [
          'Abc',
          'Polygon',
          'Abcdef',
          'TestsINeedThem',
          'TestsINeedThem2'
        ]

        result = class_names_match_report?(class_names: classes, error_report: @dangerfile.status_report[:errors])
        expect(result).to be true

      end

      it 'does not show errors when new classes have corresponding tests' do
        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/AbcTests.java' => 'class AbcTests { public void abcTest() { Abc.main([]) } }',
          'Polygon.kt' => 'open class Polygon: Shape { override fun draw() { } }',
          'project/src/androidTest/java/org/test/PolygonTest.kt' => 'class PolygonTest { fun testDraw() { Polygon().draw() } }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void writeMeATest() { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/AnotherTestClass.java' => 'class AnotherTestClass { public void testWriteMeATest() { new TestsINeedThem().writeMeATest() } }',
          'MyNewClass.java' => 'final class MyNewClass { public void testMe() { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/TestMyNewClass.java' => 'class TestMyNewClass { public void testMe() { new MyNewClass().testMe() } }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show errors when we are deleting classes' do
        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'Polygon.kt' => 'abstract class Polygon { abstract fun draw() }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void testMe() { System.out.println(""); } }'
        }

        diff = generate_deleted_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'show errors when we remove test classes for classes we refactored' do
        added_classes = {
          'Abc.kt' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'Polygon.kt' => 'data class Polygon(sides: Int) { fun draw() {} }',
          'TestsINeedThem.kt' => 'public open class TestsINeedThem { fun testMe2() { } }'
        }

        removed_tests = {
          'project/src/androidTest/java/org/test/AbcTests.java' => 'class AbcTests { public void testAbc() { Abc.main([]) } }',
          'project/src/androidTest/java/org/test/PolygonTest.java' => 'class PolygonTest { void testDraw() { Polygon(sides = 5).draw() }',
          'project/src/androidTest/java/org/test/TestsINeedThem.java' => 'class TestsINeedThem { public void testMe2() { TestsINeedThem().testMe2() } }'
        }

        diff = generate_add_diff(added_classes) + generate_deleted_diff(removed_tests)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        classes = [
          'Abc',
          'Polygon',
          'TestsINeedThem'
        ]
        
        result = class_names_match_report?(class_names: classes, error_report: @dangerfile.status_report[:errors])
        expect(result).to be true
      end

      it 'does nothing when a PR adds only tests' do
        changes_dict = {
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { fun testMethod() {} }',
          'project/src/androidTest/java/org/test/UtilsTest.kt' => 'class UtilsTest { fun testMe() {} }',
          'project/src/androidTest/java/org/test/MyHelperTest.java' => 'public class MyHelperTest { public void testMe() {} }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does nothing when a PR adds classes that dont need tests' do
        changes_dict = {
          'project/src/android/java/org/activities/MyActivity.kt' => 'class MyActivity: Activity { fun myActivity() {} }',
          'project/src/android/java/org/activities/MyJavaActivity.java' => 'class MyJavaActivity extends Activity { public void myJavaActivity() {} }',
          'project/src/android/java/org/fragments/MyFragment.kt' => 'class MyFragment: Fragment { override fun onBackPressed() {} }',
          'project/src/android/java/org/fragments/MyNewJavaFragment.java' => 'public class MyNewJavaFragment extends Fragment { public void myFragment() {} }',
          'project/src/android/java/org/module/MyModule.java' => 'public class MyModule { public void module() {} }',
          'project/src/android/java/org/view/MyRecyclerView.java' => 'public class MyRecyclerView extends RecyclerView { public List<Items> list() {} }',
          'project/src/android/java/org/view/MyViewHolder.kt' => 'class MyViewHolder { fun testMe() {} }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show that a PR with the tests bypass label is missing tests' do
        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'Abcdef.kt' => 'class Abcdef(name: String) { fun testMe() { println(""); } }',
          'TestsINeedThem2.kt' => 'public open class TestsINeedThem2 { fun testMe2() { } }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return(['unit-tests-exemption'])

        @plugin.check_missing_tests

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show errors when a PR without tests with a custom bypass label is missing tests' do
        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { fun testMethod() {} }',
          'Abcdef.kt' => 'class Abcdef(name: String) { public fun testMe() { println(""); } }'
        }

        bypass_label = 'ignore-no-tests'

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)
        allow(@plugin.github).to receive(:pr_labels).and_return([bypass_label])

        @plugin.check_missing_tests(bypass_label: bypass_label)

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'does not show that a PR adding custom classes / subclasses patterns are missing tests' do
        exceptions = [
          /ViewHelper$/
        ].freeze

        subclasses_exceptions = [
          /BaseViewWrangler/
        ].freeze

        changes_dict = {
          'Abc.java' => 'import java.utils.*;\n\n public class Abc extends BaseViewWrangler { public static void main(String[] args) { println(""); } }',
          'AbcWrangler.java' => 'import java.utils.*;\n\n abstract class AbcWrangler extends BaseViewWrangler { public abstract void wrangle(); }',
          'KotlinWrangler.kt' => 'abstract class KotlinWrangler: BaseViewWrangler { abstract fun wrangle(); }',
          'project/src/androidTest/java/org/test/ToolTest.kt' => 'class ToolTest { void testMethod() {} }',
          'AbcdefViewHelper.kt' => 'class AbcdefViewHelper(name: String) { fun testMe() { println(""); } }',
          'AbcdefgViewHelper.java' => 'public final class AbcdefgViewHelper { public static void testMe() { System.out.println(""); } }'
        }

        diff = generate_add_diff(changes_dict)
        allow(@dangerfile.git).to receive(:diff).and_return(diff)

        @plugin.check_missing_tests(classes_exceptions: exceptions, subclasses_exceptions: subclasses_exceptions)

        expect(@dangerfile.status_report[:errors]).to be_empty
      end
    end

    def generate_add_diff(changes_dict)
      changes_dict.map do |file_path, content|
        diff_str = <<~PATCH
          diff --git a/#{file_path} b/#{file_path}
          new file mode 100644
          index 0000000..fd48a22
          --- /dev/null
          +++ b/#{file_path}
          @@ -0,0 +1 @@
          +#{content}
          \\ No newline at end of file
        PATCH

        OpenStruct.new(type: 'new', path: file_path, patch: diff_str)
      end
    end

    def generate_deleted_diff(changes_dict)
      changes_dict.map do |file_path, content|
        diff_str = <<~PATCH
          diff --git a/#{file_path} b/#{file_path}
          deleted file mode 100644
          index fd48a22..0000000
          --- a/#{file_path}
          +++ /dev/null
          @@ -1 +0,0 @@
          -#{content}
          \\ No newline at end of file
        PATCH

        OpenStruct.new(type: 'deleted', path: file_path, patch: diff_str)
      end
    end

    def class_names_match_report?(class_names:, error_report:)
      error_report.all? { |str| class_names.any? { |class_name| str.include?("Please add tests for class `#{class_name}`") } }
    end
  end
end
