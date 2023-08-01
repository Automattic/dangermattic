# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::PRSizeChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.pr_size_checker
      end

      context 'when checking a PR diff size' do
        before do
          allow(@plugin.git).to receive(:added_files).and_return([])
          allow(@plugin.git).to receive(:modified_files).and_return([])
          allow(@plugin.git).to receive(:deleted_files).and_return([])
        end

        shared_examples 'using the default diff size counter without a file selector' do |type|
          let(:diff_counter_for_type) do
            type_hash = {
              insertions: :insertions,
              deletions: :deletions,
              all: :lines_of_code
            }

            type_hash[type]
          end

          it 'reports a warning when using default parameters in a PR that has larger diff than the default maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(501)

            @plugin.check_diff_size(type: type)

            expect(@dangerfile.status_report[:errors]).to be_empty
            expect(@dangerfile.status_report[:warnings]).to eq ['This PR is larger than 500 lines of changes. Please consider splitting it into smaller PRs for easier and faster reviews.']
          end

          it 'does nothing when using default parameters in a PR that has equal diff than the default maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(500)

            @plugin.check_diff_size(type: type)

            expect(@dangerfile.status_report[:errors]).to be_empty
            expect(@dangerfile.status_report[:warnings]).to be_empty
          end

          it 'does nothing when using default parameters in a PR that has smaller diff than the default maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(499)

            @plugin.check_diff_size(type: type)

            expect(@dangerfile.status_report[:errors]).to be_empty
            expect(@dangerfile.status_report[:warnings]).to be_empty
          end

          it 'reports an error using a custom message and a custom PR body size' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(600)

            custom_message = 'diff size custom message'
            @plugin.check_diff_size(type: type, max_size: 599, message: custom_message, fail_on_error: true)

            expect(@dangerfile.status_report[:warnings]).to be_empty
            expect(@dangerfile.status_report[:errors]).to eq [custom_message]
          end
        end

        shared_examples 'using a file selector to filter and count the changes in a diff' do |type, max_sizes|
          it 'reports a warning when using a files filter that will result in a diff that is too large' do
            prepare_diff_with_test_files

            @plugin.check_diff_size(
              file_selector: ->(path) { File.dirname(path).start_with?('src/test/java') },
              type: type,
              max_size: max_sizes[0]
            )

            expect(@dangerfile.status_report[:errors]).to be_empty
            expect(@dangerfile.status_report[:warnings]).to eq ['This PR is larger than 500 lines of changes. Please consider splitting it into smaller PRs for easier and faster reviews.']
          end

          it 'reports an error when using a files filter that will result in a diff that is too large, with a custom error' do
            prepare_diff_with_test_files

            custom_message = 'diff size too large custom file filter and error message'
            @plugin.check_diff_size(
              file_selector: ->(path) { File.extname(path) == '.java' },
              type: type,
              max_size: max_sizes[1],
              message: custom_message,
              fail_on_error: true
            )

            expect(@dangerfile.status_report[:warnings]).to be_empty
            expect(@dangerfile.status_report[:errors]).to eq [custom_message]
          end

          it 'does nothing when a files filter is used but the max size is greater than or equal to the diff size' do
            prepare_diff_with_test_files

            @plugin.check_diff_size(
              file_selector: ->(path) { File.extname(path).match(/^(.java|.kt)$/) },
              type: type,
              max_size: max_sizes[2]
            )

            expect(@dangerfile.status_report[:errors]).to be_empty
            expect(@dangerfile.status_report[:warnings]).to be_empty
          end
        end

        context 'with the entire diff' do
          include_examples 'using the default diff size counter without a file selector', :all
          include_examples 'using a file selector to filter and count the changes in a diff', :all, [422, 520, 1541]
        end

        context 'with the insertions in the diff' do
          include_examples 'using the default diff size counter without a file selector', :insertions
          include_examples 'using a file selector to filter and count the changes in a diff', :insertions, [200, 139, 384]
        end

        context 'with the deletions in the diff' do
          include_examples 'using the default diff size counter without a file selector', :deletions
          include_examples 'using a file selector to filter and count the changes in a diff', :deletions, [221, 380, 1157]
        end

        def prepare_diff_with_test_files
          added_test_file = 'src/test/java/org/magic/MagicTests.kt'
          added_config = 'config.xml'
          added_file = 'MyNewSorcery.java'
          modified_file1 = 'src/java/PotionIngredients.java'
          modified_file2 = 'src/java/Potion.kt'
          modified_strings = 'src/main/res/values/strings.xml'
          deleted_file1 = 'src/java/org/Fire.kt'
          deleted_file2 = 'BlackCat.kt'
          deleted_test_file = 'src/test/java/org/magic/Power.java'
          deleted_strings = 'src/main/res/values-de/strings.xml'

          allow(@plugin.git).to receive(:added_files).and_return([added_config, added_file])
          allow(@plugin.git).to receive(:modified_files).and_return([modified_file1, modified_file2, added_test_file, modified_strings])
          allow(@plugin.git).to receive(:deleted_files).and_return([deleted_file1, deleted_test_file, deleted_strings, deleted_file2])

          allow(@plugin.git).to receive(:info_for_file).with(added_test_file).and_return({ insertions: 201 })
          allow(@plugin.git).to receive(:info_for_file).with(added_config).and_return({ insertions: 311 })
          allow(@plugin.git).to receive(:info_for_file).with(added_file).and_return({ insertions: 13 })
          allow(@plugin.git).to receive(:info_for_file).with(modified_file1).and_return({ insertions: 127, deletions: 159 })
          allow(@plugin.git).to receive(:info_for_file).with(modified_file2).and_return({ insertions: 43, deletions: 37 })
          allow(@plugin.git).to receive(:info_for_file).with(modified_strings).and_return({ insertions: 432, deletions: 297 })
          allow(@plugin.git).to receive(:info_for_file).with(deleted_file1).and_return({ deletions: 246 })
          allow(@plugin.git).to receive(:info_for_file).with(deleted_file2).and_return({ deletions: 493 })
          allow(@plugin.git).to receive(:info_for_file).with(deleted_test_file).and_return({ deletions: 222 })
          allow(@plugin.git).to receive(:info_for_file).with(deleted_strings).and_return({ deletions: 593 })
        end
      end

      context 'when checking a PR body size' do
        it 'reports a warning when using default parameters in a PR that has a smaller body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('PR body')

          @plugin.check_pr_body

          expect(@dangerfile.status_report[:errors]).to be_empty
          expect(@dangerfile.status_report[:warnings]).to eq ['The PR description appears very short, less than 10 characters long. Please provide a summary of your changes in the PR description.']
        end

        it 'does nothing when using default parameters in a PR that has a bigger PR body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test PR body')

          @plugin.check_pr_body

          expect(@dangerfile.status_report[:errors]).to be_empty
          expect(@dangerfile.status_report[:warnings]).to be_empty
        end

        it 'reports a warning when using default parameters in a PR that has an equal PR body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test-')

          @plugin.check_pr_body

          expect(@dangerfile.status_report[:errors]).to be_empty
          expect(@dangerfile.status_report[:warnings]).to eq ['The PR description appears very short, less than 10 characters long. Please provide a summary of your changes in the PR description.']
        end

        it 'reports an error when using a custom message and a custom minimum PR body text length' do
          allow(@plugin.github).to receive(:pr_body).and_return('still too short message')

          custom_message = 'Custom error message'
          @plugin.check_pr_body(min_length: 25, message: custom_message, fail_on_error: true)

          expect(@dangerfile.status_report[:warnings]).to be_empty
          expect(@dangerfile.status_report[:errors]).to eq [custom_message]
        end
      end
    end
  end
end
