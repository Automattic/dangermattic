# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::CommonReleaseChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with the common_release_checker plugin' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.common_release_checker

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
      end

      context 'when changing the internal release notes' do
        it 'reports a warning when a PR on a release branch changes the internal release notes' do
          notes_file = 'RELEASE-NOTES.txt'
          allow(@plugin.git).to receive(:modified_files).and_return([notes_file])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_internal_release_notes_changed

          expect(@dangerfile).to report_warnings([format(CommonReleaseChecker::MESSAGE_INTERNAL_RELEASE_NOTES_CHANGED, notes_file)])
        end

        it 'reports a warning when a PR on a release branch changes the internal release notes using a custom filename' do
          notes_file = 'MY-CUSTOM-RELEASE-NOTES.md'
          allow(@plugin.git).to receive(:modified_files).and_return([notes_file])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_internal_release_notes_changed(release_notes_file: notes_file)

          expect(@dangerfile).to report_warnings([format(CommonReleaseChecker::MESSAGE_INTERNAL_RELEASE_NOTES_CHANGED, notes_file)])
        end

        it 'does nothing when a PR changes the release notes file on a regular branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['RELEASE-NOTES.txt'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_internal_release_notes_changed

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR changes a custom release notes file on a regular branch' do
          notes_file = 'MY-CUSTOM-RELEASE-NOTES.md'
          allow(@plugin.git).to receive(:modified_files).and_return([notes_file])
          allow(@plugin.github).to receive(:branch_for_base).and_return('develop')

          @plugin.check_internal_release_notes_changed(release_notes_file: notes_file)

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR ca warning when a PR does not change the release notes file on the release branch' do
          allow(@plugin.git).to receive(:modified_files).and_return(['./path/to/view/MyView.swift'])
          allow(@plugin.github).to receive(:branch_for_base).and_return('release/30.6')

          @plugin.check_internal_release_notes_changed

          expect(@dangerfile).to not_report
        end
      end
    end
  end
end
