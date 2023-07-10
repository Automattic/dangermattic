# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ViewCodePRChecker do
    it 'should be a plugin' do
      expect(Danger::ViewCodePRChecker.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.view_code_pr_checker
      end

      it 'warns when a PR with views do not have screenshots' do
        modified_files = ['TestView.swift', 'SimpleViewHelper.m']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'warns when an Android PR with views do not have screenshots' do
        modified_files = ['test_view.xml', 'SimpleViewHelper.kt']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'warns when a PR with buttons do not have screenshots' do
        modified_files = ['SimpleViewHelper.m', 'MyAwesomeButton.swift']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'warns when an Android PR with buttons do not have screenshots' do
        modified_files = ['SimpleViewHelper.kt', 'MyAwesomeButton.java']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'does nothing when a PR has views but has screenshots' do
        modified_files = ['TestView.swift', 'SimpleViewHelper.m']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR [![Alt text](https://myimages.com/boo)](https://digitalocean.com) Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'does nothing when an Android PR has views but has screenshots' do
        modified_files = ['TestView.kt', 'SimpleViewHelper.java']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR [![Alt text](https://myimages.com/boo)](https://digitalocean.com) Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'does nothing when a PR has buttons but has screenshots' do
        modified_files = ['SimpleViewHelper.m', 'MyButton.swift']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('PR <img src=\'https://myimages.com/boo.png\' /> Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end

      it 'does nothing when a PR doesn not have view code' do
        modified_files = ['SimpleViewHelper.m', 'MyButtonTester.swift']
        allow(@my_plugin.git).to receive(:modified_files).and_return(modified_files)

        allow(@my_plugin.github).to receive(:pr_body).and_return('Body')

        @my_plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end
    end
  end
end
