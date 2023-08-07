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
        it "reports a warning when a PR doesn't have a milestone set" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_set

          expected_warning = ['PR is not assigned to a milestone.']
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'does nothing when a PR has a milestone set' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day'
            }
          }

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

          @plugin.check_milestone_set

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end

      describe '#check_milestone_due_date' do
        it 'reports a warning when a PR has a milestone with due date within the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => '2023-06-30T23:59:01Z'
            },
            'state' => 'open'
          }

          date_one_day_before_due = DateTime.parse('2023-06-29T23:59:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_one_day_before_due)

          @plugin.check_milestone_due_date

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). This milestone is due in less than 5 days.\nPlease make sure to get it merged by then or assign it to a milestone with a later deadline."]
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'does nothing when a PR has a milestone before the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => '2023-06-30T23:59:01Z'
            },
            'state' => 'open'
          }

          more_than_five_days_before_due = DateTime.parse('2023-06-25T23:00:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(more_than_five_days_before_due)

          @plugin.check_milestone_due_date

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'reports a warning when a PR has a milestone with due date after the warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => '2023-06-30T23:59:01Z'
            },
            'state' => 'open'
          }

          date_one_day_after_due = DateTime.parse('2023-07-01T23:00:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_one_day_after_due)

          @plugin.check_milestone_due_date

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). The due date for this milestone has already passed.\nPlease make sure to get it merged by then or assign it to a milestone with a later deadline."]
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
        end

        it 'reports a warning when a PR has a milestone with due date within a custom warning days threshold' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => '2023-06-30T23:59:01Z'
            },
            'state' => 'open'
          }

          date_nine_days_before_due = DateTime.parse('2023-06-21T23:59:01Z')

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)
          allow(DateTime).to receive(:now).and_return(date_nine_days_before_due)

          @plugin.check_milestone_due_date(warning_days: 10)

          expected_warning = ["This PR is assigned to the milestone [Release Day](https://wp.com). This milestone is due in less than 10 days.\nPlease make sure to get it merged by then or assign it to a milestone with a later deadline."]
          expect(@dangerfile.status_report[:warnings]).to eq expected_warning
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

          @plugin.check_milestone_due_date

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'does nothing when a PR has a milestone but it has already passed the due date' do
          pr_json = {
            'milestone' => {
              'title' => 'Release Day',
              'html_url' => 'https://wp.com',
              'due_on' => '2023-06-30T23:59:01Z'
            },
            'state' => 'closed'
          }

          allow(@plugin.github).to receive(:pr_json).and_return(pr_json)

          @plugin.check_milestone_due_date

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it "does nothing when a PR doesn't have a milestone" do
          allow(@plugin.github).to receive(:pr_json).and_return({})

          @plugin.check_milestone_due_date

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
