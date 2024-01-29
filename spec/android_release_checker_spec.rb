# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidReleaseChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_release_checker

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
      end

      context 'when changing the release notes' do
        it 'reports a warning when a PR changes the release notes but not the Play Store strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['metadata/release_notes.txt'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to report_messages([format(CommonReleaseChecker::MESSAGE_STORE_FILE_NOT_CHANGED, 'metadata/PlayStoreStrings.po', 'metadata/release_notes.txt')])
        end

        it 'does nothing when a PR changes the release notes and the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt', 'Resources/AppStoreStrings.po'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR does not change the release notes or the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['MyView.swift', 'Resources/AppStoreStrings.tmp'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to not_report
        end
      end

      describe '#check_modified_localizable_strings_on_release' do
        it 'reports a warning when a PR on a regular branch changes the source strings.xml' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./src/main/res/values/strings.xml'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_modified_strings_on_release

          expect(@dangerfile).to report_warnings([AndroidReleaseChecker::MESSAGE_STRINGS_FILE_UPDATED])
        end

        it 'reports an error when a PR on a regular branch changes the source strings.xml' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./src/main/res/values/strings.xml'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_modified_strings_on_release(fail_on_error: true)

          expect(@dangerfile).to report_errors([AndroidReleaseChecker::MESSAGE_STRINGS_FILE_UPDATED])
        end

        it 'reports a warning when a PR on a regular branch changes a translated strings.xml' do
          allow(@plugin.git).to receive(:modified_files).and_return(['src/main/res/values-fr/strings.xml'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('trunk')

          @plugin.check_modified_strings_on_release

          expect(@dangerfile).to report_warnings([AndroidReleaseChecker::MESSAGE_STRINGS_FILE_UPDATED])
        end

        it 'does nothing when a PR changes the strings.xml on a release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['src/main/res/values/strings.xml'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_modified_strings_on_release

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR does not change the strings.xml on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/model/MyViewModel.kt'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_modified_strings_on_release

          expect(@dangerfile).to not_report
        end
      end
    end
  end
end
