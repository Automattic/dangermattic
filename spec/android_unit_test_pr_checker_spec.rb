          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'Abcdef.kt' => 'class Abcdef(name: String) { fun testMe() { println("") } }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void testMe() { System.out.println(""); } }',
        classes = [
          'Abc',
          'Polygon',
          'Abcdef',
          'TestsINeedThem',
          'TestsINeedThem2'
        ]

        result = class_names_match_report?(class_names: classes, error_report: @dangerfile.status_report[:errors])
        expect(result).to be true

          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/AbcTests.java' => 'class AbcTests { public void abcTest() { Abc.main([]) } }',
          'Polygon.kt' => 'open class Polygon: Shape { override fun draw() { } }',
          'project/src/androidTest/java/org/test/PolygonTest.kt' => 'class PolygonTest { fun testDraw() { Polygon().draw() } }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void writeMeATest() { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/AnotherTestClass.java' => 'class AnotherTestClass { public void testWriteMeATest() { new TestsINeedThem().writeMeATest() } }',
          'MyNewClass.java' => 'final class MyNewClass { public void testMe() { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/TestMyNewClass.java' => 'class TestMyNewClass { public void testMe() { new MyNewClass().testMe() } }'
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'TestsINeedThem.java' => 'public final class TestsINeedThem { public void testMe() { System.out.println(""); } }'
          'Abc.kt' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { System.out.println(""); } }',
          'project/src/androidTest/java/org/test/AbcTests.java' => 'class AbcTests { public void testAbc() { Abc.main([]) } }',
          'project/src/androidTest/java/org/test/PolygonTest.java' => 'class PolygonTest { void testDraw() { Polygon(sides = 5).draw() }',
          'project/src/androidTest/java/org/test/TestsINeedThem.java' => 'class TestsINeedThem { public void testMe2() { TestsINeedThem().testMe2() } }'
        classes = [
          'Abc',
          'Polygon',
          'TestsINeedThem'
        ]
        
        result = class_names_match_report?(class_names: classes, error_report: @dangerfile.status_report[:errors])
        expect(result).to be true
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'Abcdef.kt' => 'class Abcdef(name: String) { fun testMe() { println(""); } }',
          'Abc.java' => 'import java.utils.*;\n\n public class Abc { public static void main(String[] args) { println(""); } }',
          'Abcdef.kt' => 'class Abcdef(name: String) { public fun testMe() { println(""); } }'
          'Abc.java' => 'import java.utils.*;\n\n public class Abc extends BaseViewWrangler { public static void main(String[] args) { println(""); } }',
          'AbcdefViewHelper.kt' => 'class AbcdefViewHelper(name: String) { fun testMe() { println(""); } }',
          'AbcdefgViewHelper.java' => 'public final class AbcdefgViewHelper { public static void testMe() { System.out.println(""); } }'
      changes_dict.map do |file_path, content|
          diff --git a/#{file_path} b/#{file_path}
          new file mode 100644
          index 0000000..fd48a22
          --- /dev/null
          +++ b/#{file_path}
          @@ -0,0 +1 @@
          +#{content}
          \\ No newline at end of file

        OpenStruct.new(type: 'new', path: file_path, patch: diff_str)
      changes_dict.map do |file_path, content|
          diff --git a/#{file_path} b/#{file_path}
          deleted file mode 100644
          index fd48a22..0000000
          --- a/#{file_path}
          +++ /dev/null
          @@ -1 +0,0 @@
          -#{content}
          \\ No newline at end of file


    def class_names_match_report?(class_names:, error_report:)
      error_report.all? { |str| class_names.any? { |class_name| str.include?("Please add tests for class `#{class_name}`") } }
    end