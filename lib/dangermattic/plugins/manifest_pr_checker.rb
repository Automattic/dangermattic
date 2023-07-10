# frozen_string_literal: true

module Danger
  # Plugin to check if the Gemfile.lock was updated when changing the Gemfile in a PR.
  class ManifestPRChecker < Plugin

    # Check if the `Gemfile` file was modified without a corresponding `Gemfile.lock` update 
    def check_gemfile_lock_updated
      check_manifest_lock_updated(
        file_name: 'Gemfile',
        lock_file_name: 'Gemfile.lock',
        instruction: 'Please run `bundle install` or `bundle update <updated_gem>`'
      )
    end

      # Check if the `Podfile` file was modified without a corresponding `Podfile.lock` update 
      def check_podfile_lock_updated
        check_manifest_lock_updated(
          file_name: 'Podfile',
          lock_file_name: 'Podfile.lock',
          instruction: 'Please run `bundle exec pod install`'
        )
      end
    
    # Check if the `Package.swift` file was modified without a corresponding `Package.resolved` update 
    def check_swift_package_resolved_updated
      check_manifest_lock_updated(
        file_name: 'Package.swift',
        lock_file_name: 'Package.resolved',
        instruction: 'Please resolve the Swift packages in Xcode'
      )
    end

    private

    def check_manifest_lock_updated(file_name:, lock_file_name:, instruction:)
      manifest_modified = git.modified_files.include?(file_name)
      lock_modified = git.modified_files.include?(lock_file_name)
      
      if manifest_modified && !lock_modified
        warn("#{file_name} was changed without updating #{lock_file_name}. #{instruction}.")
      end
    end
  end
end
