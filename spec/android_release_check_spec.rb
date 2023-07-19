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

        allow(@plugin.git).to receive(:added_files).and_return([])
        allow(@plugin.git).to receive(:modified_files).and_return([])
        allow(@plugin.git).to receive(:deleted_files).and_return([])
      end

      context 'when changing the release notes' do
        it 'returns a warning when a PR changes the release notes but not the Play Store strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['metadata/release_notes.txt'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile.status_report[:warnings]).to eq ['The PlayStoreStrings.po file must be updated any time changes are made to the release notes.']
        end

        it 'does nothing when a PR changes the release notes and the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['Resources/release_notes.txt', 'Resources/AppStoreStrings.po'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'does nothing when a PR does not change the release notes or the AppStore strings file' do
          allow(@plugin.git).to receive(:modified_files).and_return(['MyView.swift', 'Resources/AppStoreStrings.tmp'])

          @plugin.check_release_notes_and_play_store_strings

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
