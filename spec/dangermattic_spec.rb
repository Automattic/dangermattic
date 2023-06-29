# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::Dmattic do
    it 'should be a plugin' do
      expect(Danger::Dmattic.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.dmattic
      end

      it 'returns warnings when the PR body is too small and the number of lines for the PR is too big' do
        allow(@my_plugin.github).to receive(:pr_body).and_return('hi')
        allow(@my_plugin.git).to receive(:lines_of_code).and_return(510)

        expect(@my_plugin.unit_test_pr_checker).to receive(:check_missing_tests)
        expect(@my_plugin.view_code_pr_checker).to receive(:view_changes_need_screenshots)

        @my_plugin.run_common_pr_checks

        expect(@dangerfile.status_report[:warnings].count).to eq 2
      end
    end
  end
end
