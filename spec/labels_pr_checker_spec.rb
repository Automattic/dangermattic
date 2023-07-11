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

        @plugin.check_labels

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'does nothing when a PR has at least one label' do
        pr_labels = ['my-label']
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check_labels

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'returns an error when a PR has a \'do not merge\' label' do
        pr_labels = ['DO NOT MERGE']
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check_labels

        expect(@dangerfile.status_report[:warnings]).to be_empty
        expect(@dangerfile.status_report[:errors].count).to eq 1
      end

      it 'returns an error when a PR has a \'not ready for merge\' label' do
        pr_labels = ['NOT READY FOR MERGE']
        allow(@plugin.github).to receive(:pr_labels).and_return(pr_labels)

        @plugin.check_labels

        expect(@dangerfile.status_report[:warnings]).to be_empty
        expect(@dangerfile.status_report[:errors].count).to eq 1
      end
    end
  end
end