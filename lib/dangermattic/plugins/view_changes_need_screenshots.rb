# frozen_string_literal: true

module Danger
  # Plugin to detect View files in a PR but without having accompanying screenshots.
  #
  # This plugin provides a method to check if view files have been modified without accompanying screenshots in the pull request body.
  #
  # @example Check if a PR needs screenshots changes check
  #
  #          # If a PR has view changes, report a warning if there are no screenshots attached
  #          checker.view_changes_need_screenshots
  #
  # @see Automattic/dangermattic
  # @tags ios, android, swift, java, kotlin, screenshots
  #
  class ViewChangesNeedScreenshots < Plugin
    VIEW_EXTENSIONS_IOS = /(View|Button)\.(swift|m)$|\.xib$|\.storyboard$/
    VIEW_EXTENSIONS_ANDROID = /(?i)(View|Button)\.(java|kt|xml)$/

    IMAGE_IN_PR_BODY_PATTERNS = [
      %r{https?://\S*\.(gif|jpg|jpeg|png|svg)},
      /!\[(.*?)\]\((.*?)\)/,
      /<img\s+[^\>]*src\s*=\s*[^\>]*>/
    ].freeze

    # Checks if view files have been modified and if a screenshot is included in the pull request body,
    # displaying a warning if view files have been modified but no screenshot is included.
    #
    # @return [void]
    def view_changes_need_screenshots
      view_files_modified = git.modified_files.any? do |file|
        VIEW_EXTENSIONS_IOS =~ file || VIEW_EXTENSIONS_ANDROID =~ file
      end

      pr_has_screenshots = IMAGE_IN_PR_BODY_PATTERNS.any? do |pattern|
        github.pr_body =~ pattern
      end

      warning = 'View files have been modified, but no screenshot is included in the pull request. ' \
                'Consider adding some for clarity.'
      warn(warning) if view_files_modified && !pr_has_screenshots
    end
  end
end
