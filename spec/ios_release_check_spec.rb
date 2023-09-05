# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::IosReleaseCheck do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.ios_release_check

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
      end

      context 'when changing the Core Data model' do
        it 'returns a warning when a PR on a release branch changes a Core Data model' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/model/Model.xcdatamodeld'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_core_data_model_changed

          expected_message = 'Do not edit an existing Core Data model in a release branch unless it hasn\'t been released to testers yet. ' \
                             'Instead create a new model version and merge back to develop soon.'
          expect(@dangerfile).to report_warnings([expected_message])
        end

        it 'does nothing when a PR changes a Core Data model on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/model/Model.xcdatamodeld'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_core_data_model_changed

          expect(@dangerfile).to do_not_report
        end

        it 'does nothing when a PR ca warning when a PR does not change a Core Data model on the release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel.swift'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_core_data_model_changed

          expect(@dangerfile).to do_not_report
        end
      end

      context 'when changing the Localizable.strings' do
        it 'returns a warning when a PR on a regular branch changes the source Localizable.strings' do
          allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('add/myfeature')

          @plugin.check_modified_localizable_strings_on_release

          expected_message = '`Localizable.strings` files should only be updated on release branches, when the translations are downloaded.'
          expect(@dangerfile).to report_warnings([expected_message])
        end

        it 'returns a warning when a PR on a regular branch changes a translated Localizable.strings' do
          allow(@plugin.git).to receive(:modified_files).and_return(['nl.lproj/Localizable.strings'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('add/myfeature1')

          @plugin.check_modified_localizable_strings_on_release

          expected_message = '`Localizable.strings` files should only be updated on release branches, when the translations are downloaded.'
          expect(@dangerfile).to report_warnings([expected_message])
        end

        it 'does nothing when a PR changes the Localizable.strings on a release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_modified_localizable_strings_on_release

          expect(@dangerfile).to do_not_report
        end

        it 'does nothing when a PR ca warning when a PR does not change the Localizable.strings on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel.swift'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('add/myfeature')

          @plugin.check_modified_localizable_strings_on_release

          expect(@dangerfile).to do_not_report
        end
      end

      context 'when changing the release notes' do
        it 'returns a warning when a PR changes the release notes but not the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to report_messages(['The `Resources/AppStoreStrings.po` file should be updated if the editorialised release notes file `Resources/release_notes.txt` is being changed.'])
        end

        it 'does nothing when a PR changes the release notes and the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt', 'Resources/AppStoreStrings.po'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to do_not_report
        end

        it 'does nothing when a PR does not change the release notes or the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['MyView.swift', 'Resources/AppStoreStrings.tmp'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to do_not_report
        end
      end
    end
  end
end
