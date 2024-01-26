# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::ViewChangesChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    shared_examples 'PR with view code changes' do |modified_files|
      before do
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)
      end

      it 'warns when a PR with view code changes does not have screenshots' do
        allow(@plugin.github).to receive(:pr_body).and_return('PR Body')

        @plugin.check

        expect(@dangerfile).to report_warnings([ViewChangesChecker::MESSAGE])
      end

      it 'does nothing when a PR with view code changes has screenshots defined in markdown' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return('PR [![Alt text](https://myimages.com/boo)](https://digitalocean.com) Body')

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has url to screenshots' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return('<a href=\'https://myimages.com/boo.jpg\'>see secreenshot</a> Body')

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has a screenshot defined with a html tag with different attributes before src' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return("see screenshot:\n<img width=300 hint=\"First screenshots\" src=\"https://github.com/bloom/DayOne-Apple/assets/4780/1f9e01a8-c63d-41d4-9ac8-fa9a5182ab55\"> body body")

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has a screenshot defined with a html tag' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return("see screenshot:\n<img src=\"https://github.com/woocommerce/woocommerce-ios/assets/1864060/17d9227d-67e8-4efb-8c26-02b81e1b19d2\" width=\"375\"> body body")

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has a video defined with a html tag with different attributes before src' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return("see video:\n<video width=300 hint=\"First video\" src=\"https://www.w3schools.com/tags/movie.mp4\"> body body")

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has a video defined with a html tag' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return("see video:\n<video src=\"https://www.w3schools.com/tags/movie.mp4\" width=\"375\"> body body")

        @plugin.check

        expect(@dangerfile).to not_report
      end

      it 'does nothing when a PR with view code changes has a video defined with a simple URL' do
        allow(@plugin.github).to receive(:pr_body)
          .and_return("see video:\nhttps://github.com/woocommerce/woocommerce-ios/assets/1864060/0e983305-5047-40a3-8829-734e0b582b96 body body")

        @plugin.check

        expect(@dangerfile).to not_report
      end
    end

    shared_examples 'PR without view code changes' do |modified_files|
      before do
        allow(@plugin.git).to receive(:modified_files).and_return(modified_files)
        allow(@plugin.github).to receive(:pr_body).and_return('Body')
        @plugin.check
      end

      it 'does nothing' do
        expect(@dangerfile).to not_report
      end
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.view_changes_checker
      end

      context 'when checking an iOS PR' do
        context 'with view code changes in Swift files' do
          include_examples 'PR with view code changes', ['TestView.swift', 'SimpleViewHelper.m']
        end

        context 'with button changes in Swift files' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'MyAwesomeButton.swift']
        end

        context 'with view code changes in ObjC files' do
          include_examples 'PR with view code changes', ['TestView.m', 'SimpleViewHelper.m']
        end

        context 'with button changes in ObjC files' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'MyAwesomeButton.m']
        end

        context 'with changes in a .xib file' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'top_bar.xib']
        end

        context 'with changes in a Storyboard' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.m', 'main_screen.storyboard']
        end

        context 'with no view changes' do
          include_examples 'PR without view code changes',
                           ['SimpleViewHelper.m', 'MyButtonTester.swift', 'Version.xcconfig']
        end
      end

      context 'when checking an Android PR' do
        context 'with view code changes in Kotlin files' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'MySimpleView.kt']
        end

        context 'with button changes in Kotlin files' do
          include_examples 'PR with view code changes', ['MyAwesomeButton.kt', 'SimpleViewHelper.java']
        end

        context 'with view code changes in Java files' do
          include_examples 'PR with view code changes', ['TestView.java', 'SimpleViewHelper.kt']
        end

        context 'with button changes in Java files' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'MyAwesomeButton.java']
        end

        context 'with view code changes in a XML file' do
          include_examples 'PR with view code changes', ['test_view.xml', 'SimpleViewHelper.kt', 'strings.xml']
        end

        context 'with button changes in a XML file' do
          include_examples 'PR with view code changes', ['SimpleViewHelper.kt', 'strings.xml', 'my_awesome_button.xml']
        end

        context 'with no view changes' do
          include_examples 'PR without view code changes', ['SimpleViewHelper.java', 'values.xml', 'MyButtonTester.kt']
        end
      end
    end
  end
end
