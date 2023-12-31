# frozen_string_literal: true

module Danger
  # Plugin to check if the a lock file (Gemfile.lock, Podfile.lock, Package.resolved) was updated when changing a manifest
  # file (Gemfile, Podfile, Package.swift) in a PR.
  #
  # @example Running manifest / lock checks
  #
  #          # Check all manifest files (Gemfile, Podfile, Package.swift) have a corresponding lock change
  #          checker.check_all_manifest_lock_updated
  #
  # @example Gemfile check
  #
  #          # Check if the Gemfile and the Gemfile.lock are both updated
  #          checker.check_gemfile_lock_updated
  #
  # @example Podfile check
  #
  #          # Check if the Podfile and the Podfile.lock are both updated
  #          checker.check_podfile_lock_updated
  #
  # @example Package.swift check
  #
  #          # Check if the Package.swift and the Package.resolved are both updated
  #          checker.check_swift_package_resolved_updated
  #
  # @see Automattic/dangermattic
  # @tags ios, android
  #
  class ManifestPRChecker < Plugin
    # Performs all the checks, asserting that changes on `Gemfile`, `Podfile` and `Package.swift` must have corresponding
    # lock file changes.
    #
    # @return [void]
    def check_all_manifest_lock_updated
      check_gemfile_lock_updated
      check_podfile_lock_updated
      check_swift_package_resolved_updated
    end

    # Check if the `Gemfile` file was modified without a corresponding `Gemfile.lock` update
    #
    # @return [void]
    def check_gemfile_lock_updated
      check_manifest_lock_updated(
        file_name: 'Gemfile',
        lock_file_name: 'Gemfile.lock',
        instruction: 'Please run `bundle install` or `bundle update <updated_gem>`'
      )
    end

    # Check if the `Podfile` file was modified without a corresponding `Podfile.lock` update
    #
    # @return [void]
    def check_podfile_lock_updated
      check_manifest_lock_updated(
        file_name: 'Podfile',
        lock_file_name: 'Podfile.lock',
        instruction: 'Please run `bundle exec pod install`'
      )
    end

    # Check if the `Package.swift` file was modified without a corresponding `Package.resolved` update
    #
    # @return [void]
    def check_swift_package_resolved_updated
      check_manifest_lock_updated(
        file_name: 'Package.swift',
        lock_file_name: 'Package.resolved',
        instruction: 'Please resolve the Swift packages in Xcode'
      )
    end

    private

    def check_manifest_lock_updated(file_name:, lock_file_name:, instruction:)
      # Find all the modified manifest files
      manifest_modified_files = git.modified_files.select { |f| File.basename(f) == file_name }

      # For each manifest file, check if the corresponding lockfile (in the same dir) was also modified
      manifest_modified_files.each do |manifest_file|
        lockfile_modified = git.modified_files.any? { |f| File.dirname(f) == File.dirname(manifest_file) && File.basename(f) == lock_file_name }
        next if lockfile_modified

        warn("`#{manifest_file}` was changed without updating its corresponding `#{lock_file_name}`. #{instruction}.")
      end
    end
  end
end
