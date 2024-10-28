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
        it 'reports a warning when a PR changed the Gemfile but not the Gemfile.lock' do
          modified_files = ['Gemfile']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expected_warning = format(ManifestPRChecker::MESSAGE, 'Gemfile', 'Gemfile.lock', 'Please run `bundle install` or `bundle update <updated_gem>`')
          expect(@dangerfile).to report_warnings([expected_warning])
        end

        it 'reports no warnings when both the Gemfile and the Gemfile.lock were updated' do
          modified_files = ['Gemfile', 'Gemfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expect(@dangerfile).to not_report
        end

        it 'reports no warnings when only the Gemfile.lock was updated' do
          modified_files = ['Gemfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_gemfile_lock_updated

          expect(@dangerfile).to not_report
        end
      end

      describe 'CocoaPods' do
        it 'reports a warning when a PR changed the Podfile but not the Podfile.lock' do
          modified_files = ['Podfile']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expected_warning = format(ManifestPRChecker::MESSAGE, 'Podfile', 'Podfile.lock', 'Please run `bundle exec pod install`')
          expect(@dangerfile).to report_warnings([expected_warning])
        end

        it 'reports no warnings when both the Podfile and the Podfile.lock were updated' do
          modified_files = ['Podfile', 'Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expect(@dangerfile).to not_report
        end

        it 'reports a warning when a PR changed a custom located Podfile but not the corresponding Podfile.lock' do
          modified_files = ['./path/to/Podfile', './my/Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expected_warning = format(ManifestPRChecker::MESSAGE, './path/to/Podfile', 'Podfile.lock', 'Please run `bundle exec pod install`')
          expect(@dangerfile).to report_warnings([expected_warning])
        end

        it 'reports multiple warnings when a PR changed multiple custom located Podfiles but not the corresponding Podfile.lock' do
          modified_files = ['./dir1/Podfile', './dir2/Podfile', './dir3/Podfile', './dir1/Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expected_warnings = [
            format(ManifestPRChecker::MESSAGE, './dir2/Podfile', 'Podfile.lock', 'Please run `bundle exec pod install`'),
            format(ManifestPRChecker::MESSAGE, './dir3/Podfile', 'Podfile.lock', 'Please run `bundle exec pod install`')
          ]
          expect(@dangerfile).to report_warnings(expected_warnings)
        end

        it 'reports no warnings when both custom located Podfile`s and their corresponding Podfile.lock were updated' do
          modified_files = ['./my/path/to/Podfile', './another/path/to/Podfile', './my/path/to/Podfile.lock', './another/path/to/Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expect(@dangerfile).to not_report
        end

        it 'reports no warnings when only the Podfile.lock was updated' do
          modified_files = ['Podfile.lock']
          allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

          @plugin.check_podfile_lock_updated

          expect(@dangerfile).to not_report
        end
      end

      describe 'Swift Package Manager' do
        describe '#check_swift_package_resolved_updated' do
          it 'reports a warning when a PR changed the Package.swift but not the Package.resolved' do
            modified_files = ['Package.swift']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated

            expected_warning = format(ManifestPRChecker::MESSAGE, 'Package.swift', 'Package.resolved', 'Please resolve the Swift packages in Xcode')
            expect(@dangerfile).to report_warnings([expected_warning])
          end

          it 'reports no warnings when both the Package.swift and the Package.resolved were updated' do
            modified_files = ['Package.swift', 'Package.resolved']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated

            expect(@dangerfile).to not_report
          end

          it 'reports no warnings when only the Package.resolved was updated' do
            modified_files = ['Package.resolved']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated

            expect(@dangerfile).to not_report
          end
        end

        describe '#check_swift_package_resolved_updated_strict' do
          it 'reports a warning when a PR changed the specific Package.swift but not its Package.resolved' do
            modified_files = ['Apps/App1/Package.swift', 'Apps/App2/Package.swift', 'Apps/App2/Package.resolved']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated_strict(
              manifest_path: 'Apps/App1/Package.swift',
              manifest_lock_path: 'Apps/App1/Package.resolved'
            )

            expected_warning = format(ManifestPRChecker::MESSAGE, 'Apps/App1/Package.swift', 'Package.resolved', 'Please resolve the Swift packages in Xcode')
            expect(@dangerfile).to report_warnings([expected_warning])
          end

          it 'reports no warning when both the specific Package.swift and Package.resolved were updated' do
            modified_files = ['Apps/App1/Package.swift', 'Apps/App1/Package.resolved']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated_strict(
              manifest_path: 'Apps/App1/Package.swift',
              manifest_lock_path: 'Apps/App1/Package.resolved'
            )

            expect(@dangerfile).to not_report
          end

          it 'reports no warning when the specific Package.swift was not modified' do
            modified_files = ['Apps/App2/Package.swift', 'Apps/App2/Package.resolved']
            allow(@plugin.git).to receive(:modified_files).and_return(modified_files)

            @plugin.check_swift_package_resolved_updated_strict(
              manifest_path: 'Apps/App1/Package.swift',
              manifest_lock_path: 'Apps/App1/Package.resolved'
            )

            expect(@dangerfile).to not_report
          end
        end
      end
    end
  end
end
