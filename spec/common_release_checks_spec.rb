# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::CommonReleaseChecks do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with the common_release_checks plugin' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.common_release_checks

        allow(@plugin.git).to receive(:added_files).and_return([])
        allow(@plugin.git).to receive(:modified_files).and_return([])
        allow(@plugin.git).to receive(:deleted_files).and_return([])
      end

      context 'when changing the internal release notes' do
        it 'returns a warning when a PR on a release branch changes the internal release notes' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/model/RELEASE-NOTES.txt'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_internal_release_notes_changed

          expected_message = <<~WARNING
            This PR contains changes to `RELEASE-NOTES.txt`.
            Note that these changes won't affect the final version of the release notes as this version is in code freeze.
            Please, get in touch with a release manager if you want to update the final release notes.
          WARNING

          expect(@dangerfile.status_report[:warnings]).to eq [expected_message]
        end

        it 'does nothing when a PR changes a Core Data model on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./RELEASE-NOTES.txt'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_internal_release_notes_changed

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'does nothing when a PR ca warning when a PR does not change a Core Data model on the release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/MyView.swift'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_internal_release_notes_changed

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
