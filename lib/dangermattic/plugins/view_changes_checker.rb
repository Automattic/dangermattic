# frozen_string_literal: true

module Danger
  # Plugin to make sure View file changes in a Pull Request will have accompanying screenshots in the PR description.
  #
  # @example Check if a PR changing views needs to have screenshots
  #
  #          # If a PR has view changes, report a warning if there are no screenshots attached
  #          view_changes_checker.check
  #
  # @see Automattic/dangermattic
  # @tags ios, android, swift, java, kotlin, screenshots
  #
  class ViewChangesChecker < Plugin
    VIEW_EXTENSIONS_IOS = /(View|Button)\.(swift|m)$|\.xib$|\.storyboard$/
    VIEW_EXTENSIONS_ANDROID = /(?i)(View|Button)\.(java|kt|xml)$/

    MEDIA_IN_PR_BODY_PATTERNS = [
      %r{https?://\S*\.(gif|jpg|jpeg|png|svg)},
      %r{https?://\S*\.(mp4|avi|mov|mkv)},
      %r{https?://\S*github\S+/\S+/assets/\d+/},
      /!\[(.*?)\]\((.*?)\)/,
      /<img\s+[^>]*src\s*=\s*[^>]*>/,
      /<video\s+[^>]*src\s*=\s*[^>]*>/
    ].freeze

    MESSAGE = 'View files have been modified, but no screenshot or video is included in the pull request. ' \
              'Consider adding some for clarity.'

    # Checks if view files have been modified and if a screenshot or video is included in the pull request body,
    # displaying a warning if view files have been modified but no screenshot or video is included.
    #
    # @return [void]
    def check
      view_files_modified = git.modified_files.any? do |file|
        VIEW_EXTENSIONS_IOS =~ file || VIEW_EXTENSIONS_ANDROID =~ file
      end

      pr_has_media = MEDIA_IN_PR_BODY_PATTERNS.any? do |pattern|
        github.pr_body =~ pattern
      end

      warn(MESSAGE) if view_files_modified && !pr_has_media
    end
  end
end
