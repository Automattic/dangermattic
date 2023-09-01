# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidStringsChecks do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_strings_checks

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])

        stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
      end

      context 'when changing strings.xml files' do
        it 'returns a warning when a PR adds a string resource reference inside a strings.xml file' do
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
            This PR adds a translatable entry which references another string resource; this usually causes issues with translations.
            Please make sure to set the `translatable="false"` attribute:
            File `#{strings_xml_path}`:
            ```diff
            +  <string name="screen_title">@string/app_name</string>
            ```
          WARNING

          expect(@dangerfile.status_report[:warnings]).to eq [expected_warning]
        end

        it 'returns multiple warnings when a PR adds multiple string resource references inside multiple strings.xml files' do
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
            This PR adds a translatable entry which references another string resource; this usually causes issues with translations.
            Please make sure to set the `translatable="false"` attribute:
            File `#{main_strings_xml}`:
            ```diff
            +  <string name="screen_title">@string/app_name</string>
            ```
          WARNING

          expected_warning2 = <<~WARNING
            This PR adds a translatable entry which references another string resource; this usually causes issues with translations.
            Please make sure to set the `translatable="false"` attribute:
            File `#{main_strings_xml}`:
            ```diff
            +  <string name="screen_button">@string/button</string>
            ```
          WARNING

          expected_warning3 = <<~WARNING
            This PR adds a translatable entry which references another string resource; this usually causes issues with translations.
            Please make sure to set the `translatable="false"` attribute:
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

          expect(@dangerfile.status_report[:warnings]).to be_empty
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

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
