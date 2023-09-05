# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::AndroidReleaseCheck do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.android_release_check

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
      end

      context 'when changing the release notes' do
        it 'returns a warning when a PR changes the release notes but not the Play Store strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['metadata/release_notes.txt'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to report_messages(['The `metadata/PlayStoreStrings.po` file should be updated if the editorialised release notes file `metadata/release_notes.txt` is being changed.'])
        end

        it 'does nothing when a PR changes the release notes and the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt', 'Resources/AppStoreStrings.po'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to do_not_report
        end

        it 'does nothing when a PR does not change the release notes or the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['MyView.swift', 'Resources/AppStoreStrings.tmp'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile).to do_not_report
        end
      end
    end
  end
end
