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
          allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
        end

        shared_examples 'using the default diff size counter, without a file selector' do |type|
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

            expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, described_class::DEFAULT_MAX_DIFF_SIZE)])
          end

          it 'does nothing when using default parameters in a PR that has equal diff than the default maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(500)

            @plugin.check_diff_size(type: type)

            expect(@dangerfile).to not_report
          end

          it 'does nothing when using default parameters in a PR that has smaller diff than the default maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(499)

            @plugin.check_diff_size(type: type)

            expect(@dangerfile).to not_report
          end

          context 'when reporting a custom error or warning with a custom max_size' do
            shared_examples 'reporting diff size custom warnings or errors' do |fail_on_error, message|
              it 'reports an error using a custom message and a custom PR body size' do
                allow(@plugin.git).to receive(diff_counter_for_type).and_return(600)

                if message
                  @plugin.check_diff_size(type: type, max_size: 599, message: message, fail_on_error: fail_on_error)
                else
                  @plugin.check_diff_size(type: type, max_size: 599, fail_on_error: fail_on_error)
                end

                message ||= format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 599)

                expect_warning_or_error(fail_on_error: fail_on_error, message: message)
              end
            end

            context 'when fail on error is false and a custom message is given' do
              include_examples 'reporting diff size custom warnings or errors', false, 'this is my custom warning message'
            end

            context 'when fail on error is false' do
              include_examples 'reporting diff size custom warnings or errors', false
            end

            context 'when fail on error is true' do
              include_examples 'reporting diff size custom warnings or errors', true
            end

            context 'when a custom error message is given and fail on error is true' do
              include_examples 'reporting diff size custom warnings or errors', true, 'this is my custom error message'
            end
          end
        end

        shared_examples 'using a file selector to filter and count the changes in a diff' do |type, max_sizes|
          context 'when using a files filter that will regard the diff as too large' do
            it 'reports a warning' do
              prepare_diff_with_test_files

              @plugin.check_diff_size(
                file_selector: ->(path) { File.dirname(path).start_with?('src/test/java') },
                type: type,
                max_size: max_sizes[0]
              )

              expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, max_sizes[0])])
            end

            it 'reports a custom error' do
              prepare_diff_with_test_files

              custom_message = 'diff size too large custom file filter and error message'
              @plugin.check_diff_size(
                file_selector: ->(path) { File.extname(path) == '.java' },
                type: type,
                max_size: max_sizes[1],
                message: custom_message,
                fail_on_error: true
              )

              expect(@dangerfile).to report_errors([custom_message])
            end
          end

          it 'does nothing when a files filter is used but the max size is greater than or equal to the diff size' do
            prepare_diff_with_test_files

            @plugin.check_diff_size(
              file_selector: ->(path) { File.extname(path).match(/^(.java|.kt)$/) },
              type: type,
              max_size: max_sizes[2]
            )

            expect(@dangerfile).to not_report
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

            allow(@plugin.git).to receive_messages(added_files: [added_config, added_file], modified_files: [modified_file1, modified_file2, added_test_file, modified_strings], deleted_files: [deleted_file1, deleted_test_file, deleted_strings, deleted_file2])

            allow(@plugin.git).to receive(:diff).and_return(instance_double(Git::Diff))
            expected_files = { added_test_file => {}, added_config => {}, added_file => {}, modified_file1 => {}, modified_file2 => {}, modified_strings => {}, deleted_file1 => {}, deleted_file2 => {}, deleted_test_file => {}, deleted_strings => {} }
            allow(@plugin.git.diff).to receive(:stats).and_return({ files: expected_files })

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

        context 'with the entire diff' do
          include_examples 'using the default diff size counter, without a file selector', :all
          include_examples 'using a file selector to filter and count the changes in a diff', :all, [422, 520, 1541]
        end

        context 'with the insertions in the diff' do
          include_examples 'using the default diff size counter, without a file selector', :insertions
          include_examples 'using a file selector to filter and count the changes in a diff', :insertions, [200, 139, 384]
        end

        context 'with the deletions in the diff' do
          include_examples 'using the default diff size counter, without a file selector', :deletions
          include_examples 'using a file selector to filter and count the changes in a diff', :deletions, [221, 380, 1157]
        end
      end

      context 'when checking a PR body size' do
        it 'reports a warning when using default parameters in a PR that has a smaller body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('PR body')

          @plugin.check_pr_body

          expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, described_class::DEFAULT_MIN_PR_BODY)])
        end

        it 'does nothing when using default parameters in a PR that has a bigger PR body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test PR body')

          @plugin.check_pr_body

          expect(@dangerfile).to not_report
        end

        it 'reports a warning when using default parameters in a PR that has an equal PR body text length than the default minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test-')

          @plugin.check_pr_body

          expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, described_class::DEFAULT_MIN_PR_BODY)])
        end

        context 'when reporting a custom error or warning with a custom min_length' do
          shared_examples 'reporting PR length check custom warnings or errors' do |fail_on_error, message|
            it 'reports an error when using a custom message and a custom minimum PR body text length' do
              allow(@plugin.github).to receive(:pr_body).and_return('still too short message')

              if message
                @plugin.check_pr_body(min_length: 25, message: message, fail_on_error: fail_on_error)
              else
                @plugin.check_pr_body(min_length: 25, fail_on_error: fail_on_error)
              end

              message ||= format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, 25)

              expect_warning_or_error(fail_on_error: fail_on_error, message: message)
            end
          end

          context 'when fail on error is false and a custom message is given' do
            include_examples 'reporting PR length check custom warnings or errors', false, 'this is my custom warning message'
          end

          context 'when fail on error is false' do
            include_examples 'reporting PR length check custom warnings or errors', false
          end

          context 'when fail on error is true' do
            include_examples 'reporting PR length check custom warnings or errors', true
          end

          context 'when a custom error message is given and fail on error is true' do
            include_examples 'reporting PR length check custom warnings or errors', true, 'this is my custom error message'
          end
        end
      end

      def expect_warning_or_error(fail_on_error:, message:)
        if fail_on_error
          expect(@dangerfile).to report_errors([message])
        else
          expect(@dangerfile).to report_warnings([message])
        end
      end
    end
  end
end
