# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ViewCodePRChecker do
    it 'should be a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    shared_examples 'PR with view code changes' do |modified_files|
      before do
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)
      end

      it 'warns when a PR with view code changes does not have screenshots' do
        allow(@plugin.github).to receive(:pr_body).and_return('PR Body')

        @plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings].count).to eq 1
      end

      it 'does nothing when a PR with view code changes has screenshots' do
        allow(@plugin.github).to receive(:pr_body).and_return('PR [![Alt text](https://myimages.com/boo)](https://digitalocean.com) Body')

        @plugin.view_changes_need_screenshots

        expect(@dangerfile.status_report[:warnings]).to be_empty
      end
    end

    shared_examples 'PR without view code changes' do |modified_files|
      before do
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)
        allow(@plugin.github).to receive(:pr_body).and_return('Body')
        @plugin.view_changes_need_screenshots
      end
    
      it 'does nothing' do
        expect(@dangerfile.status_report[:warnings]).to be_empty
      end
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.view_code_pr_checker
      end

      context 'iOS PR has view code changes in Swift files' do
        include_examples 'PR with view code changes', ['TestView.swift', 'SimpleViewHelper.m']
      end

      context 'iOS PR has button changes in Swift files' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'MyAwesomeButton.swift']
      end

      context 'iOS PR has view code changes in ObjC files' do
        include_examples 'PR with view code changes', ['TestView.m', 'SimpleViewHelper.m']
      end

      context 'iOS PR has button changes in ObjC files' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'MyAwesomeButton.m']
      end

      context 'iOS PR has changes in a .xib file' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'top_bar.xib']
      end

      context 'iOS PR has changes in a Storyboard' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'main_screen.storyboard']
      end

      context 'iOS PR has no view changes' do
        include_examples 'PR without view code changes', ['SimpleViewHelper.m', 'MyButtonTester.swift', 'Version.xcconfig']
      end

      context 'Android PR has view code changes in Kotlin files' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'MySimpleView.kt']
      end

      context 'Android PR has button changes in Kotlin files' do
        include_examples 'PR with view code changes', ['MyAwesomeButton.kt', 'SimpleViewHelper.java']
      end

      context 'Android PR has view code changes in Java files' do
        include_examples 'PR with view code changes', ['TestView.java', 'SimpleViewHelper.kt']
      end

      context 'Android PR has button changes in Java files' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'MyAwesomeButton.java']
      end

      context 'Android PR has view code changes in a XML file' do
        include_examples 'PR with view code changes', ['test_view.xml', 'SimpleViewHelper.kt', 'strings.xml']
      end

      context 'Android PR has button changes in a XML file' do
        include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'strings.xml', 'my_awesome_button.xml']
      end

      context 'Android PR has no view changes' do
        include_examples 'PR without view code changes', ['SimpleViewHelper.java', 'values.xml', 'MyButtonTester.kt']
      end
    end
  end
end
