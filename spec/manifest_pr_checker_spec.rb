# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ManifestPRChecker do
    it 'should be a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.manifest_pr_checker
      end

      it 'returns a warning when a PR changed the Gemfile but not the Gemfile.lock' do
        modified_files = ['Gemfile']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_gemfile_lock_updated

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'returns no warnings when both the Gemfile and the Gemfile.lock were updated' do
        modified_files = ['Gemfile', 'Gemfile.lock']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_gemfile_lock_updated

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'returns a warning when a PR changed the Podfile but not the Podfile.lock' do
        modified_files = ['Podfile']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_podfile_lock_updated

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'returns no warnings when both the Podfile and the Podfile.lock were updated' do
        modified_files = ['Podfile', 'Podfile.lock']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_podfile_lock_updated

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'returns a warning when a PR changed the Package.swift but not the Package.resolved' do
        modified_files = ['Package.swift']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_swift_package_resolved_updated

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'returns no warnings when both the Package.swift and the Package.resolved were updated' do
        modified_files = ['Package.swift', 'Package.resolved']
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

        @plugin.check_swift_package_resolved_updated

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end
    end
  end
end
