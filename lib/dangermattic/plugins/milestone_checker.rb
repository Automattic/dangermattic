# frozen_string_literal: true

module Danger
  # Plugin for performing checks on a milestone associated with a pull request.
  class MilestoneChecker < Plugin
    DEFAULT_WARNING_DAYS = 5

    # Checks if the pull request is assigned to a milestone.
    def check_milestone_set(fail_on_error: false)
      return unless milestone.nil?

      message = 'PR is not assigned to a milestone.'
      if fail_on_error
        failure(message, sticky: false)
      else
        warn(message, sticky: false)
      end
    end

    # Checks if the pull request's milestone is due to finish within a certain number of days.
    #
    # @param warning_days [Integer] Number of days to warn before the milestone due date (default: DEFAULT_WARNING_DAYS).
    # @param if_no_milestone [Symbol] Action to take if the pull request is not assigned to a milestone. Possible values:
    #                 - :warn (default): Reports a warning.
    #                 - :error: Reports an error.
    #                 - :none or nil: Takes no action.
    def check_milestone_due_date(warning_days: DEFAULT_WARNING_DAYS, if_no_milestone: :warn)
      if milestone.nil?
        check_milestone_set(fail_on_error: if_no_milestone == :error)
        return
      end

      milestone_due_date = milestone['due_on']
      return unless github.pr_json['state'] != 'closed' && milestone_due_date

      today = DateTime.now
      due_date = DateTime.parse(milestone_due_date)

      warning_threshold = warning_days * 24 * 60 * 60
      time_before_due_date = due_date.to_time.to_i - today.to_time.to_i
      return unless time_before_due_date <= warning_threshold

      message_text = "This PR is assigned to the milestone [#{milestone['title']}](#{milestone['html_url']}). "
      message_text += if time_before_due_date.positive?
                        "This milestone is due in less than #{warning_days} days.\n"
                      else
                        "The due date for this milestone has already passed.\n"
                      end
      message_text += 'Please make sure to get it merged by then or assign it to a milestone with a later deadline.'

      warn(message_text)
    end

    def milestone
      github.pr_json['milestone']
    end
  end
end
