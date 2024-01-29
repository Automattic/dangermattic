# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::LabelsChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.labels_checker
      end

      context 'with required labels' do
        it 'reports a custom error when a PR does not have at least one label' do
          allow(@plugin.github).to receive(:pr_labels).and_return([])

          error = 'PR is missing at least one label.'
          @plugin.check(required_labels: [//], required_labels_error: error)

          expect(@dangerfile).to report_errors([error])
        end

        it 'does nothing when a PR has at least one label' do
          pr_labels = ['my-label']
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          @plugin.check(required_labels: [//])

          expect(@dangerfile).to not_report
        end

        it 'reports an error containing the required labels when a PR does not meet the label requirements' do
          pr_labels = ['random other label', '[feature] magic', 'wizard needed', 'type: fantasy']
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          @plugin.check(
            required_labels: [/^\[feature\]/, /^\[type\]:/]
          )

          expect(@dangerfile).to report_errors(['PR is missing label(s) matching: `^\[type\]:`'])
        end

        it 'reports a custom error when a PR has custom label requirements' do
          pr_labels = ['random label', 'feature: magic', 'wizard needed', 'another type: test']
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          custom_labels_error = 'Please add at least one of the required labels.'

          @plugin.check(
            required_labels: [/^feature:/, /^type:/],
            required_labels_error: custom_labels_error
          )

          expect(@dangerfile).to report_errors([custom_labels_error])
        end

        it 'does nothing when custom required labels are correctly set in the PR' do
          pr_labels = [
            'some other label',
            'type: fantasy',
            'milestone: 1.0',
            'feature: time travel',
            'wizard needed'
          ]
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          @plugin.check(
            required_labels: [/^feature:/, /^type:/]
          )

          expect(@dangerfile).to not_report
        end
      end

      context 'with recommended labels' do
        it 'reports a warning containing the recommended labels when a PR does not meet the label requirements' do
          pr_labels = ['random other label', 'milestone: rc']
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          @plugin.check(
            recommended_labels: [/^feature:/, /^milestone:/, /^\[type\]/]
          )

          expect(@dangerfile).to report_warnings(['PR is missing label(s) matching: `^feature:`, `^\[type\]`'])
        end

        it 'reports a custom warning when a PR has custom label requirements' do
          pr_labels = ['random other label', 'feature: myFeature', 'Milestone: beta']
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          custom_labels_warning = 'Please add at least one feature and milestone label in the expected formats.'

          @plugin.check(
            recommended_labels: [/^feature:/, /^milestone:/],
            recommended_labels_warning: custom_labels_warning
          )

          expect(@dangerfile).to report_warnings([custom_labels_warning])
        end

        it 'does nothing when custom recommended labels are correctly set in the PR' do
          pr_labels = [
            '[feature]: time travel',
            '[type]: prototype',
            '[milestone]: prototype',
            'another random label'
          ]
          allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

          @plugin.check(
            recommended_labels: [/^\[feature\]:/, /^\[type\]:/]
          )

          expect(@dangerfile).to not_report
        end
      end

      context 'with \'do not merge\' labels' do
        it 'reports an error when a PR has a \'do not merge\' label' do
          pr_label = 'DO NOT MERGE'
          allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

          @plugin.check

          expect(@dangerfile).to report_errors(["This PR is tagged with `#{pr_label}` label(s)."])
        end

        it 'reports an error when a PR has a custom label for not merging' do
          pr_label = 'please dont merge'
          allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

          labels = ['blocked', pr_label]
          @plugin.check(
            do_not_merge_labels: labels
          )

          expect(@dangerfile).to report_errors(["This PR is tagged with `#{pr_label}` label(s)."])
        end
      end

      it 'reports the right errors and warning when combining the check parameters' do
        do_not_merge_label = 'blocked'
        pr_labels = [do_not_merge_label, 'type: test', 'milestone: alpha']
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        custom_labels_error = "Please add at least one label in the 'type: issueType' format."
        custom_labels_warning = "Please add at least one label in the 'feature: myFeatureName' format."

        @plugin.check(
          do_not_merge_labels: [do_not_merge_label],
          required_labels: [/^type:/, /^feature:/],
          required_labels_error: custom_labels_error,
          recommended_labels: [/^bug-triage$/],
          recommended_labels_warning: custom_labels_warning
        )

        expect(@dangerfile.status_report[:warnings]).to eq([custom_labels_warning])
        expect(@dangerfile.status_report[:errors]).to contain_exactly(
          "This PR is tagged with `#{do_not_merge_label}` label(s).",
          custom_labels_error
        )
      end
    end
  end
end
