# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::LabelsPRChecker do
    it 'should be a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.labels_pr_checker
      end

      it 'returns a warning when a PR does not have labels' do
        pr_labels = []
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check

        expect(@dangerfile.status_report[:errors]).to be_empty
        expect(@dangerfile.status_report[:warnings]).to eq(['PR is missing at least one label.'])
      end

      it 'does nothing when a PR has at least one label' do
        pr_labels = ['my-label']
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check

        expect(@dangerfile.status_report[:errors]).to be_empty
        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'returns an error when a PR has a \'do not merge\' label' do
        pr_label = 'DO NOT MERGE'
        allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

        @plugin.check

        expect(@dangerfile.status_report[:warnings]).to be_empty
        expect(@dangerfile.status_report[:errors]).to eq(["This PR is tagged with '#{pr_label}' label."])
      end

      it 'returns an error when a PR has a custom label for not merging' do
        pr_label = 'please dont merge'
        allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

        @plugin.check(
          do_not_merge_label: pr_label
        )

        expect(@dangerfile.status_report[:warnings]).to be_empty
        expect(@dangerfile.status_report[:errors]).to eq(["This PR is tagged with '#{pr_label}' label."])
      end

      it 'returns a warning when a PR has custom label requirements' do
        pr_label = 'random other label'
        allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

        @plugin.check(
          required_labels: [/feature: .*/]
        )

        expect(@dangerfile.status_report[:errors]).to be_empty
        expect(@dangerfile.status_report[:warnings]).to eq(['Please add the required labels for this project.'])
      end

      it 'returns a custom warning when a PR has custom label requirements' do
        pr_label = 'random other label'
        allow(@plugin.github).to receive(:pr_labels).and_return([pr_label])

        custom_labels_warning = "Please add at least one label in the 'feature: myFeatureName' format."

        @plugin.check(
          required_labels: [/feature: .*/],
          required_labels_warning: custom_labels_warning
        )

        expect(@dangerfile.status_report[:errors]).to be_empty
        expect(@dangerfile.status_report[:warnings]).to eq([custom_labels_warning])
      end

      it 'does nothing when custom labels are correctly set in the PR' do
        pr_labels = [
          'feature: time travel',
          'type: prototype'
        ]
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check(
          required_labels: [/feature: .*/, /type: .*/]
        )

        expect(@dangerfile.status_report[:errors]).to be_empty
        expect(@dangerfile.status_report[:warnings]).to be_empty
      end
    end
  end
end
