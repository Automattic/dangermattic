# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::MilestoneChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.milestone_checker
      end

      describe '#check_milestone_set' do
        context 'when there is no milestone set' do
          it "reports a warning when a PR doesn't have a milestone set" do
            allow(@plugin.github).to receive(:pr_json).and_return({})

            @plugin.check_milestone_set

            expected_warning = ['PR is not assigned to a milestone.']
            expect(@dangerfile).to report_warnings(expected_warning)
          end

          it "reports an error when a PR doesn't have a milestone set" do
            allow(@plugin.github).to receive(:pr_json).and_return({})

            @plugin.check_milestone_set(report_type: :error)

            expected_error = ['PR is not assigned to a milestone.']
            expect(@dangerfile).to report_errors(expected_error)
          end
        end

        context 'when there is a milestone set' do
          it 'does nothing when a PR has a milestone set' do
            pr_json = {
              'milestone' => {
                'title' => 'Release Day'
              }
            }

            allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

            @plugin.check_milestone_set

            expect(@dangerfile).to not_report
          end

          it 'does nothing when an error is expected but the PR has a milestone set' do
            pr_json = {
              'milestone' => {
                'title' => 'Release Day'
              }
            }

            allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

            @plugin.check_milestone_set(report_type: :error)

            expect(@dangerfile).to not_report
          end
        end
      end

      describe '#check_milestone_due_date' do
        it 'reports a warning when a PR has a milestone with due date within the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => DateTime.parse('2023-06-30T23:59:01Z')
            },
            'state' => 'open'
          }

          date_one_day_before_due = DateTime.parse('2023-06-29T23:59:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_one_day_before_due)

          @plugin.check_milestone_due_date(days_before_due: 5)

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). This milestone is due in less than 5 days.\nPlease make sure to get it merged by then or assign it to a milestone with a later deadline."]
          expect(@dangerfile).to report_warnings(expected_warning)
        end

        it 'does nothing when a PR has a milestone before the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => DateTime.parse('2023-06-30T23:59:01Z')
            },
            'state' => 'open'
          }

          more_than_five_days_before_due = DateTime.parse('2023-06-25T23:00:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(more_than_five_days_before_due)

          @plugin.check_milestone_due_date(days_before_due: 5)

          expect(@dangerfile).to not_report
        end

        it 'reports an error when a PR has a milestone with due date after the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => DateTime.parse('2023-06-30T23:59:01Z')
            },
            'state' => 'open'
          }

          date_one_day_after_due = DateTime.parse('2023-07-01T23:00:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_one_day_after_due)

          @plugin.check_milestone_due_date(days_before_due: 5, report_type: :error)

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). The due date for this milestone has already passed.\nPlease assign it to a milestone with a later deadline or check whether the release for this milestone has already been finished."]
          expect(@dangerfile).to report_errors(expected_warning)
        end

        it 'reports a warning when a PR has a milestone with due date within a custom warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => DateTime.parse('2023-06-30T23:59:01Z')
            },
            'state' => 'open'
          }

          date_nine_days_before_due = DateTime.parse('2023-06-21T23:59:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_nine_days_before_due)

          @plugin.check_milestone_due_date(days_before_due: 10)

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). This milestone is due in less than 10 days.\nPlease make sure to get it merged by then or assign it to a milestone with a later deadline."]
          expect(@dangerfile).to report_warnings(expected_warning)
        end

        it 'does nothing when a PR has a milestone without a due date' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com'
            },
            'state' => 'open'
          }

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

          @plugin.check_milestone_due_date(days_before_due: 5)

          expect(@dangerfile).to not_report
        end

        it 'does nothing when a PR has a milestone but it has already passed the due date' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => DateTime.parse('2023-06-30T23:59:01Z')
            },
            'state' => 'closed'
          }

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

          @plugin.check_milestone_due_date(days_before_due: 5)

          expect(@dangerfile).to not_report
        end

        it "reports a warning when asked to do so when a PR doesn't have a milestone set" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_due_date(days_before_due: 5, report_type_if_no_milestone: :warning)

          expected_warning = ['PR is not assigned to a milestone.']
          expect(@dangerfile).to report_warnings(expected_warning)
        end

        it "reports an error when asked to do so when a PR doesn't have a milestone set" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_due_date(days_before_due: 5, report_type_if_no_milestone: :error)

          expected_error = ['PR is not assigned to a milestone.']
          expect(@dangerfile).to report_errors(expected_error)
        end

        it "does nothing when asked to do so when a PR doesn't have a milestone set" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_due_date(days_before_due: 5, report_type_if_no_milestone: :none)

          expect(@dangerfile).to not_report
        end

        it "does nothing when nil is used and a PR doesn't have a milestone set" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_due_date(days_before_due: 5, report_type_if_no_milestone: nil)

          expect(@dangerfile).to not_report
        end
      end
    end
  end
end
