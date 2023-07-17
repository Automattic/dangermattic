# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ManifestPRChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.manifest_pr_checker
      end

      describe 'Bundler' do
        it 'returns a warning when a PR changed the Gemfile but not the Gemfile.lock' do
          modified_files = ['Gemfile']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expected_warning = ['Gemfile was changed without updating Gemfile.lock. Please run `bundle install` or `bundle update <updated_gem>`.']
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'returns no warnings when both the Gemfile and the Gemfile.lock were updated' do
          modified_files = ['Gemfile', 'Gemfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'returns no warnings when only the Gemfile.lock was updated' do
          modified_files = ['Gemfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end

      describe 'CocoaPods' do
        it 'returns a warning when a PR changed the Podfile but not the Podfile.lock' do
          modified_files = ['Podfile']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expected_warning = ['Podfile was changed without updating Podfile.lock. Please run `bundle exec pod install`.']
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'returns no warnings when both the Podfile and the Podfile.lock were updated' do
          modified_files = ['Podfile', 'Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'returns no warnings when only the Podfile.lock was updated' do
          modified_files = ['Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end

      describe 'Swift Package Manager' do
        it 'returns a warning when a PR changed the Package.swift but not the Package.resolved' do
          modified_files = ['Package.swift']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_swift_package_resolved_updated

          expected_warning = ['Package.swift was changed without updating Package.resolved. Please resolve the Swift packages in Xcode.']
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'returns no warnings when both the Package.swift and the Package.resolved were updated' do
          modified_files = ['Package.swift', 'Package.resolved']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_swift_package_resolved_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'returns no warnings when only the Package.resolved was updated' do
          modified_files = ['Package.resolved']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_swift_package_resolved_updated

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
