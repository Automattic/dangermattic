# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidStringsChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_strings_checker

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])

        stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
      end

      context 'when changing strings.xml files' do
        it 'reports a warning when a PR adds a string resource reference inside a strings.xml file' do
          strings_xml_path = './src/main/res/values/strings.xml'
          allow(@plugin.git).to receive(:modified_files).and_return([strings_xml_path])

          strings_xml_diff = <<~STRINGS
            diff --git a/src/main/res/values/strings.xml b/src/main/res/values/strings.xml
            index 5794d472..772e2b99 100644
            --- a/src/main/res/values/strings.xml
            +++ b/src/main/res/values/strings.xml
            @@ -1,3 +1,6 @@
             <?xml version="1.0" encoding="UTF-8"?>
             <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="select_categories">Select categories</string>
            +  <string name="video_quality">Video Quality</string>
            +  <string name="screen_title">@string/app_name</string>
             </resources>
          STRINGS

          diff = GitDiffStruct.new('modified', strings_xml_path, strings_xml_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(strings_xml_path).and_return(diff)

          @plugin.check_strings_do_not_refer_resource

          expected_warning = <<~WARNING
            #{AndroidStringsChecker::MESSAGE}
            File `#{strings_xml_path}`:
            ```diff
            +  <string name="screen_title">@string/app_name</string>
            ```
          WARNING

          expect(@dangerfile).to report_warnings([expected_warning])
        end

        it 'reports multiple warnings when a PR adds multiple string resource references inside multiple strings.xml files' do
          main_strings_xml = './src/main/res/values/strings.xml'
          ptbr_strings_xml = './src/main/res/values-pt-rBR/strings.xml'
          strings_xml_paths = [main_strings_xml, ptbr_strings_xml]
          allow(@plugin.git).to receive(:modified_files).and_return(strings_xml_paths)

          main_xml_diff = <<~STRINGS
            diff --git a/src/main/res/values/strings.xml b/src/main/res/values/strings.xml
            index 5794d472..772e2b99 100644
            --- a/src/main/res/values/strings.xml
            +++ b/src/main/res/values/strings.xml
            @@ -1,3 +1,6 @@
             <?xml version="1.0" encoding="UTF-8"?>
             <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="select_categories">Select categories</string>
            +  <string name="video_quality">Video Quality</string>
            +  <string name="screen_title">@string/app_name</string>
            +  <string name="screen_button">@string/button</string>
            -  <string name="field_hint">@string/hint</string>
             </resources>
          STRINGS

          main_diff = GitDiffStruct.new('modified', main_strings_xml, main_xml_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(main_strings_xml).and_return(main_diff)

          ptbr_xml_diff = <<~STRINGS
            diff --git a/src/main/res/values-pt-rBR/strings.xml b/src/main/res/values-pt-rBR/strings.xml
            index 5794d472..772e2b99 100644
            --- a/src/main/res/values-pt-rBR/strings.xml
            +++ b/src/main/res/values-pt-rBR/strings.xml
            @@ -1,3 +1,6 @@
            <?xml version="1.0" encoding="UTF-8"?>
            <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="video_quality">Video Quality</string>
            +  <string name="popup_title">@string/app_name_title</string>
            -  <string name="toast">@string/common_toast</string>
            </resources>
          STRINGS

          ptbr_diff = GitDiffStruct.new('modified', ptbr_strings_xml, ptbr_xml_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(ptbr_strings_xml).and_return(ptbr_diff)

          @plugin.check_strings_do_not_refer_resource

          expected_warning = <<~WARNING
            #{AndroidStringsChecker::MESSAGE}
            File `#{main_strings_xml}`:
            ```diff
            +  <string name="screen_title">@string/app_name</string>
            ```
          WARNING

          expected_warning2 = <<~WARNING
            #{AndroidStringsChecker::MESSAGE}
            File `#{main_strings_xml}`:
            ```diff
            +  <string name="screen_button">@string/button</string>
            ```
          WARNING

          expected_warning3 = <<~WARNING
            #{AndroidStringsChecker::MESSAGE}
            File `#{ptbr_strings_xml}`:
            ```diff
            +  <string name="popup_title">@string/app_name_title</string>
            ```
          WARNING

          expect(@dangerfile.status_report[:warnings]).to contain_exactly(expected_warning, expected_warning2, expected_warning3)
        end

        it 'does nothing when a PR adds a string resource reference inside a strings.xml file but with translatable=\"false\"' do
          strings_xml_path = './src/main/res/values/strings.xml'
          allow(@plugin.git).to receive(:modified_files).and_return([strings_xml_path])

          strings_xml_diff = <<~STRINGS
            diff --git a/src/main/res/values/strings.xml b/src/main/res/values/strings.xml
            index 5794d472..772e2b99 100644
            --- a/src/main/res/values/strings.xml
            +++ b/src/main/res/values/strings.xml
            @@ -1,3 +1,6 @@
             <?xml version="1.0" encoding="UTF-8"?>
             <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="select_categories">Select categories</string>
            +  <string name="video_quality">Video Quality</string>
            +  <string name="screen_title" translatable="false">@string/app_name</string>
             </resources>
          STRINGS

          diff = GitDiffStruct.new('modified', strings_xml_path, strings_xml_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(strings_xml_path).and_return(diff)

          @plugin.check_strings_do_not_refer_resource

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR adds strings without resource references' do
          strings_xml_path = './src/main/res/values/strings.xml'
          allow(@plugin.git).to receive(:modified_files).and_return([strings_xml_path])

          strings_xml_diff = <<~STRINGS
            diff --git a/src/main/res/values/strings.xml b/src/main/res/values/strings.xml
            index 5794d472..772e2b99 100644
            --- a/src/main/res/values/strings.xml
            +++ b/src/main/res/values/strings.xml
            @@ -1,3 +1,6 @@
             <?xml version="1.0" encoding="UTF-8"?>
             <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="select_categories">Select categories</string>
            +  <string name="video_quality">Video Quality</string>
             </resources>
          STRINGS

          diff = GitDiffStruct.new('modified', strings_xml_path, strings_xml_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(strings_xml_path).and_return(diff)

          @plugin.check_strings_do_not_refer_resource

          expect(@dangerfile).to not_report
        end
      end

      context 'when checking that existing strings are not modified' do
        let(:source_strings_xml) { 'WordPress/src/main/res/values/strings.xml' }

        def stub_diff(path, patch)
          allow(@plugin.git).to receive(:modified_files).and_return([path])
          diff = GitDiffStruct.new('modified', path, patch)
          allow(@plugin.git).to receive(:diff_for_file).with(path).and_return(diff)
        end

        it 'reports an error when the value of an existing string is modified in place' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
            +  <string name="greeting">Hi there</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expected_error = <<~ERROR
            #{AndroidStringsChecker::STRING_MODIFIED_MESSAGE}
            File `#{source_strings_xml}`, string `greeting`:
            ```diff
            -  <string name="greeting">Hello</string>
            +  <string name="greeting">Hi there</string>
            ```
          ERROR

          expect(@dangerfile).to report_errors([expected_error])
        end

        it 'does nothing when a brand new string key is added' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,2 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            +  <string name="greeting">Hello</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'does nothing when an existing string key is removed' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,3 +1,2 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a string is only reordered (value unchanged)' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,4 +1,4 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
               <string name="other">Other</string>
            +  <string name="greeting">Hello</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a key is renamed (old key removed, new key added)' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
            +  <string name="greeting_v2">Hello</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'ignores modifications to non-translatable strings' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="app_name" translatable="false">WordPress</string>
            +  <string name="app_name" translatable="false">WordPress.com</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'ignores localized strings.xml files by default' do
          localized_path = 'WordPress/src/main/res/values-fr/strings.xml'
          stub_diff(localized_path, <<~STRINGS)
            diff --git a/#{localized_path} b/#{localized_path}
            index 5794d472..772e2b99 100644
            --- a/#{localized_path}
            +++ b/#{localized_path}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Bonjour</string>
            +  <string name="greeting">Salut</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified

          expect(@dangerfile).to not_report
        end

        it 'reports an error for each modified string across multiple source files' do
          wp_path = 'WordPress/src/main/res/values/strings.xml'
          jp_path = 'WordPress/src/jetpack/res/values/strings.xml'
          allow(@plugin.git).to receive(:modified_files).and_return([wp_path, jp_path])

          wp_diff = GitDiffStruct.new('modified', wp_path, <<~STRINGS)
            diff --git a/#{wp_path} b/#{wp_path}
            index 5794d472..772e2b99 100644
            --- a/#{wp_path}
            +++ b/#{wp_path}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
            +  <string name="greeting">Hi</string>
             </resources>
          STRINGS
          allow(@plugin.git).to receive(:diff_for_file).with(wp_path).and_return(wp_diff)

          jp_diff = GitDiffStruct.new('modified', jp_path, <<~STRINGS)
            diff --git a/#{jp_path} b/#{jp_path}
            index 5794d472..772e2b99 100644
            --- a/#{jp_path}
            +++ b/#{jp_path}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="farewell">Bye</string>
            +  <string name="farewell">Goodbye</string>
             </resources>
          STRINGS
          allow(@plugin.git).to receive(:diff_for_file).with(jp_path).and_return(jp_diff)

          @plugin.check_existing_strings_not_modified

          wp_error = <<~ERROR
            #{AndroidStringsChecker::STRING_MODIFIED_MESSAGE}
            File `#{wp_path}`, string `greeting`:
            ```diff
            -  <string name="greeting">Hello</string>
            +  <string name="greeting">Hi</string>
            ```
          ERROR

          jp_error = <<~ERROR
            #{AndroidStringsChecker::STRING_MODIFIED_MESSAGE}
            File `#{jp_path}`, string `farewell`:
            ```diff
            -  <string name="farewell">Bye</string>
            +  <string name="farewell">Goodbye</string>
            ```
          ERROR

          expect(@dangerfile.status_report[:errors]).to contain_exactly(wp_error, jp_error)
        end

        it 'can be configured to report a warning instead of an error' do
          stub_diff(source_strings_xml, <<~STRINGS)
            diff --git a/#{source_strings_xml} b/#{source_strings_xml}
            index 5794d472..772e2b99 100644
            --- a/#{source_strings_xml}
            +++ b/#{source_strings_xml}
            @@ -1,3 +1,3 @@
             <resources xmlns:tools="http://schemas.android.com/tools">
            -  <string name="greeting">Hello</string>
            +  <string name="greeting">Hi there</string>
             </resources>
          STRINGS

          @plugin.check_existing_strings_not_modified(report_type: :warning)

          expect(@dangerfile.status_report[:warnings].count).to eq(1)
          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end
    end
  end
end
