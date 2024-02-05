# frozen_string_literal: true

module Danger
  # This plugin checks whether a pull request is assigned to a milestone and whether the milestone's due date is approaching.
  #
  # @example Check if a milestone is set
  #
  #          # Check if PR is assigned to a milestone
  #          checker.check_milestone_set
  #
  #          # Check if PR is assigned to a milestone, reporting an error if that's not the case
  #          checker.check_milestone_set(report_type: :error)
  #
  # @example Run a milestone check
  #
  #          # Check if milestone due date is approaching, reporting a warning if the milestone is in less than 5 days
  #          checker.check_milestone_due_date
  #
  # @example Run a milestone check with custom parameters
  #
  #          # Check if milestone due date is within 3 days, reporting an error if the due date has passed and in case there's no milestone set
  #          checker.check_milestone_due_date(days_before_due: 3, report_type: :error, report_type_if_no_milestone: :error)
  #
  # @example Run a milestone check with a custom milestone behaviour parameter
  #
  #          # Check if milestone due date is approaching and don't report anything if no milestone is assigned
  #          checker.check_milestone_due_date(report_type_if_no_milestone: :none)
  #
  # @see Automattic/dangermattic
  # @tags milestone, github, process
  #
  class MilestoneChecker < Plugin
    DEFAULT_DAYS_THRESHOLD = 5

    # Checks if the pull request is assigned to a milestone.
    #
    # @return [void]
    def check_milestone_set(report_type: :warning)
      return unless milestone.nil?

      message = 'PR is not assigned to a milestone.'
      reporter.report(message: message, type: report_type)
    end

    # Checks if the pull request's milestone is due to finish within a certain number of days.
    #
    # @param days_before_due [Integer] Number of days before the milestone due date for the check to apply (default: DEFAULT_DAYS_THRESHOLD).
    # @param report_type [Symbol] (optional) The type of message for when the PR is has passed over the `days_before_due` threshold. Types: :error, :warning (default), :message.
    # @param report_type_if_no_milestone [Symbol] The type of message for when the PR is not assigned to a milestone. Types: :error, :warning (default), :message. You can also pass :none to not leave a message when there is no milestone.
    #
    # @return [void]
    def check_milestone_due_date(days_before_due: DEFAULT_DAYS_THRESHOLD, report_type: :warning, report_type_if_no_milestone: :warning)
      if milestone.nil?
        check_milestone_set(report_type: report_type_if_no_milestone)
        return
      end

      return unless pr_state != 'closed' && milestone_due_date

      today = DateTime.now

      seconds_threshold = days_before_due * 24 * 60 * 60
      time_before_due_date = milestone_due_date.to_time.to_i - today.to_time.to_i
      return unless time_before_due_date <= seconds_threshold

      message_text = "This PR is assigned to the milestone [#{milestone_title}](#{milestone_url}). "
      message_text += if time_before_due_date.positive?
                        "This milestone is due in less than #{days_before_due} days.\n" \
                          'Please make sure to get it merged by then or assign it to a milestone with a later deadline.'
                      else
                        "The due date for this milestone has already passed.\n" \
                          'Please assign it to a milestone with a later deadline or check whether the release for this milestone has already been finished.'
                      end

      reporter.report(message: message_text, type: report_type)
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
