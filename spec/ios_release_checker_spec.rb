# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::IosReleaseChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.ios_release_checker

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
      end

      context 'when changing the Core Data model' do
        it 'reports a warning when a PR on a release branch changes a Core Data model' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/model/Model.xcdatamodeld'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_core_data_model_changed

          expect(@dangerfile).to report_warnings([IosReleaseChecker::MESSAGE_CORE_DATA_UPDATED])
        end

        it 'does nothing when a PR changes a Core Data model on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/model/Model.xcdatamodeld'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_core_data_model_changed

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR ca warning when a PR does not change a Core Data model on the release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel.swift'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_core_data_model_changed

          expect(@dangerfile).to not_report
        end
      end

      context 'when changing the Localizable.strings files' do
        describe '#check_modified_localizable_strings_on_release' do
          it 'reports a warning when a PR on a regular branch changes the source Localizable.strings' do
            allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_localizable_strings_on_release

            expect(@dangerfile).to report_warnings([IosReleaseChecker::MESSAGE_STRINGS_FILE_UPDATED])
          end

          it 'reports a warning when a PR on a regular branch changes a translated Localizable.strings' do
            allow(@plugin.git).to receive(:modified_files).and_return(['nl.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('trunk')

            @plugin.check_modified_localizable_strings_on_release

            expect(@dangerfile).to report_warnings([IosReleaseChecker::MESSAGE_STRINGS_FILE_UPDATED])
          end

          it 'does nothing when a PR changes the Localizable.strings on a release branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

            @plugin.check_modified_localizable_strings_on_release

            expect(@dangerfile).to not_report
          end

          it 'does nothing when a PR does not change the Localizable.strings on a regular branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel.swift'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_localizable_strings_on_release

            expect(@dangerfile).to not_report
          end
        end

        describe '#check_modified_en_strings_on_regular_branch' do
          it 'reports a warning when a PR on a release branch changes the source Localizable.strings' do
            allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

            @plugin.check_modified_en_strings_on_regular_branch

            expect(@dangerfile).to report_warnings([IosReleaseChecker::MESSAGE_BASE_STRINGS_FILE_UPDATED])
          end

          it 'does nothing when a PR changes the Localizable.strings on a regular branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['en.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_en_strings_on_regular_branch

            expect(@dangerfile).to not_report
          end

          it 'does nothing when a PR on a release branch changes a translated Localizable.strings' do
            allow(@plugin.git).to receive(:modified_files).and_return(['nl.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

            @plugin.check_modified_en_strings_on_regular_branch

            expect(@dangerfile).to not_report
          end

          it 'does nothing when a PR does not change the Localizable.strings on a release branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel2.swift'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

            @plugin.check_modified_en_strings_on_regular_branch

            expect(@dangerfile).to not_report
          end
        end

        describe '#check_modified_translations_on_release_branch' do
          it 'reports a warning when a PR on a regular branch changes a translation file' do
            allow(@plugin.git).to receive(:modified_files).and_return(['be.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_translations_on_release_branch

            expect(@dangerfile).to report_warnings([IosReleaseChecker::MESSAGE_TRANSLATION_FILE_UPDATED])
          end

          it 'does nothing when a PR changes a translation string on a release branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['fr.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

            @plugin.check_modified_translations_on_release_branch

            expect(@dangerfile).to not_report
          end

          it 'does nothing when a PR on a regular branch changes the source Localizable.strings' do
            allow(@plugin.git).to receive(:modified_files).and_return(['./en.lproj/Localizable.strings'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_translations_on_release_branch

            expect(@dangerfile).to not_report
          end

          it 'does nothing when a PR does not change a translation file on a regular branch' do
            allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel3.swift'])
            allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

            @plugin.check_modified_translations_on_release_branch

            expect(@dangerfile).to not_report
          end
        end
      end

      context 'when changing the release notes' do
        it 'reports a warning when a PR changes the release notes but not the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to report_messages([format(CommonReleaseChecker::MESSAGE_STORE_FILE_NOT_CHANGED, 'Resources/AppStoreStrings.po', 'Resources/release_notes.txt')])
        end

        it 'does nothing when a PR changes the release notes and the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt', 'Resources/AppStoreStrings.po'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR does not change the release notes or the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['MyView.swift', 'Resources/AppStoreStrings.tmp'])

          @plugin.check_release_notes_and_app_store_strings

          expect(@dangerfile).to not_report
        end
      end
    end
  end
end
