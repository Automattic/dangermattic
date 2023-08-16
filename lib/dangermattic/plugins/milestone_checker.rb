# frozen_string_literal: true

module Danger
  # Plugin for performing checks on a milestone associated with a pull request.
  class MilestoneChecker < Plugin
    DEFAULT_DAYS_THRESHOLD = 5

    # Checks if the pull request is assigned to a milestone.
    def check_milestone_set(fail_on_error: false)
      return unless milestone.nil?

      message = 'PR is not assigned to a milestone.'
      sticky = false
      if fail_on_error
        failure(message, sticky: sticky)
      else
        warn(message, sticky: sticky)
      end
    end

    # Checks if the pull request's milestone is due to finish within a certain number of days.
    #
    # @param days_before_due [Integer] Number of days before the milestone due date for the check to apply (default: DEFAULT_DAYS_THRESHOLD).
    # @param if_no_milestone [Symbol] Action to take if the pull request is not assigned to a milestone. Possible values:
    #                 - :warn (default): Reports a warning.
    #                 - :error: Reports an error.
    #                 - :none or nil: Takes no action.
    def check_milestone_due_date(days_before_due: DEFAULT_DAYS_THRESHOLD, if_no_milestone: :warn)
      if milestone.nil?
        case if_no_milestone
        when :warn
          check_milestone_set(fail_on_error: false)
        when :error
          check_milestone_set(fail_on_error: true)
        end
        return
      end

      return unless pr_state != 'closed' && milestone_due_date

      today = DateTime.now
      due_date = DateTime.parse(milestone_due_date)

      seconds_threshold = days_before_due * 24 * 60 * 60
      time_before_due_date = due_date.to_time.to_i - today.to_time.to_i
      return unless time_before_due_date <= seconds_threshold

      message_text = "This PR is assigned to the milestone [#{milestone_title}](#{milestone_url}). "
      message_text += if time_before_due_date.positive?
                        "This milestone is due in less than #{days_before_due} days.\n"
                      else
                        "The due date for this milestone has already passed.\n"
                      end
      message_text += 'Please make sure to get it merged by then or assign it to a milestone with a later deadline.'

      warn(message_text)
    end

    private

    def milestone
      github.pr_json['milestone']
    end

    def milestone_due_date
      milestone['due_on']
    end

    def milestone_title
      milestone['title']
    end

    def milestone_url
      milestone['html_url']
    end

    def pr_state
      github.pr_json['state']
    end
  end
end
