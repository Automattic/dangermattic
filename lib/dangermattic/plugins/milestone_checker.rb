# frozen_string_literal: true

module Danger
  # Plugin for performing checks on a milestone associated with a pull request.
  class MilestoneChecker < Plugin
    DEFAULT_WARNING_DAYS = 5

    # Checks if the pull request's milestone is expiring within a certain number of days.
    #
    # @param needs_milestone [Boolean] Whether a milestone is required for the pull request.
    # If true, will report a warning when there is no milestone assigned to the pull request.
    # @param warning_days [Integer] Number of days to warn before the milestone due date (default: DEFAULT_WARNING_DAYS).
    def check_milestone_due_date(needs_milestone: true, warning_days: DEFAULT_WARNING_DAYS)
      milestone = github.pr_json['milestone']

      if milestone.nil?
        warn('PR is not assigned to a milestone.', sticky: false) if needs_milestone
        return
      end

      milestone_due_date = milestone['due_on']
      return unless github.pr_json['state'] != 'closed' && milestone_due_date

      today = DateTime.now
      due_date = DateTime.parse(milestone_due_date)

      warning_threshold = warning_days * 24 * 60 * 60
      time_before_due_date = due_date.to_time.to_i - today.to_time.to_i
      return unless time_before_due_date <= warning_threshold

      message_text = "This PR is assigned to the milestone [#{milestone['title']}](#{milestone['html_url']}) "
      message_text += if time_before_due_date.positive?
                        "which is expiring in less than #{warning_days} days.\n"
                      else
                        "which has already expired.\n"
                      end
      message_text += 'Please make sure to get it merged by then or assign it to a later expiring milestone.'

      warn(message_text)
    end
  end
end
