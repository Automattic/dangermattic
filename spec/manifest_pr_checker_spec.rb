# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ManifestPRChecker do
    it 'should be a plugin' do
      expect(Danger::ManifestPRChecker.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.manifest_pr_checker
      end

      it 'returns an error when a PR changed the Gemfile but not Gemfile.lock' do
        modified_files = ['Gemfile']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        @my_plugin.check_gemfile_lock_updated

        expect(@dangerfile.status_report[:errors].count).to eq 1
      end

      it 'returns no errors when both Gemfile and Gemfile.lock were updated' do
        modified_files = ['Gemfile', 'Gemfile.lock']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        @my_plugin.check_gemfile_lock_updated

        expect(@dangerfile.status_report[:errors]).to be_empty
      end

      it 'returns an error when a PR changed the Package.swift but not Package.resolved' do
        modified_files = ['Package.swift']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        @my_plugin.check_swift_package_resolved_updated

        expect(@dangerfile.status_report[:errors].count).to eq 1
      end

      it 'returns no errors when both Package.swift and Package.resolved were updated' do
        modified_files = ['Package.swift', 'Package.resolved']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        @my_plugin.check_swift_package_resolved_updated

        expect(@dangerfile.status_report[:errors]).to be_empty
      end
    end
  end
end
