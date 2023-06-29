# frozen_string_literal: true

module Danger
  # Entry point plugin, grouping checks for different platforms and build phases
  class Dmattic < Plugin
    def run_common_pr_checks
      run_pr_format_checks
      unit_test_pr_checker.check_missing_tests
      view_code_pr_checker.view_changes_need_screenshots
    end

    def run_pr_format_checks
      warn('Please provide a summary of the changes in the Pull Request description') if github.pr_body.length < 5
      warn('Please keep the Pull Request small, breaking it down into multiple ones if necessary') if git.lines_of_code > 500
    end

    def run_android_pr_checks
      warn 'TODO: common PR checks for Android'
    end

    def run_ios_pr_checks
      manifest_pr_checker.check_swift_package_resolved_updated
      swiftlint.lint_files
    end

    def run_common_post_build
      warn 'TODO: common post build checks and artifact highlights'
    end

    def run_ios_post_build
      warn 'TODO: common post build iOS'
    end

    def run_android_post_build
      warn 'TODO: common post build Android'
    end
  end
end
