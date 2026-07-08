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

          it 'reports a warning when using default parameters in a PR that has larger diff than the maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(501)

            @plugin.check_diff_size(max_size: 500, type: type)

            expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 500)])
          end

          it 'does nothing when using default parameters in a PR that has equal diff than the maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(500)

            @plugin.check_diff_size(max_size: 500, type: type)

            expect(@dangerfile).to not_report
          end

          it 'does nothing when using default parameters in a PR that has smaller diff than the maximum' do
            allow(@plugin.git).to receive(diff_counter_for_type).and_return(499)

            @plugin.check_diff_size(max_size: 500, type: type)

            expect(@dangerfile).to not_report
          end

          context 'when reporting a custom error or warning with a custom max_size' do
            shared_examples 'reporting diff size custom warnings or errors' do |report_type, message|
              it 'reports an error using a custom message and a custom PR body size' do
                allow(@plugin.git).to receive(diff_counter_for_type).and_return(600)

                if message
                  @plugin.check_diff_size(max_size: 599, type: type, message: message, report_type: report_type)
                else
                  @plugin.check_diff_size(max_size: 599, type: type, report_type: report_type)
                end

                message ||= format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 599)

                expect_warning_or_error(report_type: report_type, message: message)
              end
            end

            context 'when fail on error is false and a custom message is given' do
              it_behaves_like 'reporting diff size custom warnings or errors', false, 'this is my custom warning message'
            end

            context 'when fail on error is false' do
              it_behaves_like 'reporting diff size custom warnings or errors', false
            end

            context 'when fail on error is true' do
              it_behaves_like 'reporting diff size custom warnings or errors', true
            end

            context 'when a custom error message is given and fail on error is true' do
              it_behaves_like 'reporting diff size custom warnings or errors', true, 'this is my custom error message'
            end
          end
        end

        shared_examples 'using a file selector to filter and count the changes in a diff' do |type, max_sizes|
          context 'when using a files filter that will regard the diff as too large' do
            it 'reports a warning' do
              prepare_diff_with_test_files

              @plugin.check_diff_size(
                max_size: max_sizes[0],
                file_selector: ->(path) { File.dirname(path).start_with?('src/test/java') },
                type: type
              )

              expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, max_sizes[0])])
            end

            it 'reports a custom error' do
              prepare_diff_with_test_files

              custom_message = 'diff size too large custom file filter and error message'
              @plugin.check_diff_size(
                max_size: max_sizes[1],
                file_selector: ->(path) { File.extname(path) == '.java' },
                type: type,
                message: custom_message,
                report_type: :error
              )

              expect(@dangerfile).to report_errors([custom_message])
            end
          end

          it 'does nothing when a files filter is used but the max size is greater than or equal to the diff size' do
            prepare_diff_with_test_files

            @plugin.check_diff_size(
              max_size: max_sizes[2],
              file_selector: ->(path) { File.extname(path).match(/^(.java|.kt)$/) },
              type: type
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
            # Populate stats hash directly with insertions/deletions data for the optimized code path
            expected_files = {
              added_test_file => { insertions: 201 },
              added_config => { insertions: 311 },
              added_file => { insertions: 13 },
              modified_file1 => { insertions: 127, deletions: 159 },
              modified_file2 => { insertions: 43, deletions: 37 },
              modified_strings => { insertions: 432, deletions: 297 },
              deleted_file1 => { deletions: 246 },
              deleted_file2 => { deletions: 493 },
              deleted_test_file => { deletions: 222 },
              deleted_strings => { deletions: 593 }
            }
            allow(@plugin.git.diff).to receive(:stats).and_return({ files: expected_files })
          end
        end

        context 'with the entire diff' do
          it_behaves_like 'using the default diff size counter, without a file selector', :all
          it_behaves_like 'using a file selector to filter and count the changes in a diff', :all, [422, 520, 1541]
        end

        context 'with the insertions in the diff' do
          it_behaves_like 'using the default diff size counter, without a file selector', :insertions
          it_behaves_like 'using a file selector to filter and count the changes in a diff', :insertions, [200, 139, 384]
        end

        context 'with the deletions in the diff' do
          it_behaves_like 'using the default diff size counter, without a file selector', :deletions
          it_behaves_like 'using a file selector to filter and count the changes in a diff', :deletions, [221, 380, 1157]
        end

        context 'when using a line_selector to exclude comment and blank lines' do
          # Counts a changed line only if, once trimmed, it is neither empty nor the start of a comment.
          let(:code_line_selector) do
            lambda do |line|
              stripped = line.strip
              !(stripped.empty? || stripped.start_with?('//', '/*', '*', '*/'))
            end
          end

          # 4 added code lines (fun/val/return/}) + 1 removed code line, plus comment and blank lines that must be ignored.
          let(:kotlin_patch) do
            <<~PATCH
              diff --git a/Foo.kt b/Foo.kt
              index 1234567..89abcde 100644
              --- a/Foo.kt
              +++ b/Foo.kt
              @@ -1,2 +1,10 @@
               package com.example
              +
              +// a single line comment
              +/* a block comment */
              +/** kdoc opening */
              + * kdoc continuation line
              +fun foo(): Int {
              +    val x = 1
              +    return x
              +}
              -val removedCode = 0
              -// removed comment
            PATCH
          end

          before do
            stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
            allow(@plugin.git).to receive_messages(added_files: ['Foo.kt'], modified_files: [], deleted_files: [])
            allow(@plugin.git).to receive(:diff_for_file).with('Foo.kt').and_return(GitDiffStruct.new('added', 'Foo.kt', kotlin_patch))
          end

          it 'reports a warning when the non-comment, non-blank changes exceed the max (type :all counts 5)' do
            @plugin.check_diff_size(max_size: 4, type: :all, line_selector: code_line_selector)

            expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 4)])
          end

          it 'does nothing when the non-comment, non-blank changes are within the max (type :all counts 5)' do
            @plugin.check_diff_size(max_size: 5, type: :all, line_selector: code_line_selector)

            expect(@dangerfile).to not_report
          end

          it 'counts only added code lines for :insertions (counts 4)' do
            @plugin.check_diff_size(max_size: 3, type: :insertions, line_selector: code_line_selector)

            expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 3)])
          end

          it 'does nothing for :insertions when the added code lines are within the max (counts 4)' do
            @plugin.check_diff_size(max_size: 4, type: :insertions, line_selector: code_line_selector)

            expect(@dangerfile).to not_report
          end

          it 'counts only removed code lines for :deletions (counts 1)' do
            @plugin.check_diff_size(max_size: 0, type: :deletions, line_selector: code_line_selector)

            expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 0)])
          end

          it 'does nothing for :deletions when the removed code lines are within the max (counts 1)' do
            @plugin.check_diff_size(max_size: 1, type: :deletions, line_selector: code_line_selector)

            expect(@dangerfile).to not_report
          end

          it 'exposes the filtered counts through the size helpers' do
            expect(@plugin.diff_size(line_selector: code_line_selector)).to eq(5)
            expect(@plugin.insertions_size(line_selector: code_line_selector)).to eq(4)
          end

          context 'when combined with a file_selector' do
            before do
              excluded_test_file = 'src/test/java/FooTest.kt'
              allow(@plugin.git).to receive_messages(added_files: ['Foo.kt', excluded_test_file], modified_files: [], deleted_files: [])
              allow(@plugin.git).to receive(:diff_for_file).with(excluded_test_file).and_return(GitDiffStruct.new('added', excluded_test_file, kotlin_patch))
            end

            it 'only counts lines in files accepted by the file_selector' do
              # Both files carry the same patch (5 code lines each); excluding the test file must keep the count at 5, not 10.
              file_selector = ->(path) { !path.include?('src/test') }

              expect(
                @plugin.diff_size(file_selector: file_selector, line_selector: code_line_selector)
              ).to eq(5)
            end
          end

          context 'without a line_selector (default numstats path)' do
            before do
              allow(@plugin.git).to receive(:diff).and_return(instance_double(Git::Diff))
              allow(@plugin.git.diff).to receive(:stats).and_return({ files: { 'Foo.kt' => { insertions: 9, deletions: 2 } } })
            end

            it 'counts every changed line including comments and blanks (counts 11)' do
              @plugin.check_diff_size(max_size: 10, type: :all, file_selector: ->(_path) { true })

              expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, 10)])
            end
          end
        end

        it 'raises an ArgumentError when given an unknown diff size type' do
          expect { @plugin.check_diff_size(max_size: 100, type: :unknown) }.to raise_error(ArgumentError)
        end
      end

      context 'when checking a PR body size' do
        it 'reports a warning when using default parameters in a PR that has a smaller body text length than the minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('PR body')

          @plugin.check_pr_body(min_length: 15)

          expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, 15)])
        end

        it 'does nothing when using default parameters in a PR that has a bigger PR body text length than the minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test PR body')

          @plugin.check_pr_body(min_length: 10)

          expect(@dangerfile).to not_report
        end

        it 'reports a warning when using default parameters in a PR that has an equal PR body text length than the minimum' do
          allow(@plugin.github).to receive(:pr_body).and_return('some test-')

          @plugin.check_pr_body(min_length: 10)

          expect(@dangerfile).to report_warnings([format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, 10)])
        end

        context 'when reporting a custom error or warning with a custom min_length' do
          shared_examples 'reporting PR length check custom warnings or errors' do |report_type, message|
            it 'reports an error when using a custom message and a custom minimum PR body text length' do
              allow(@plugin.github).to receive(:pr_body).and_return('still too short message')

              if message
                @plugin.check_pr_body(min_length: 25, message: message, report_type: report_type)
              else
                @plugin.check_pr_body(min_length: 25, report_type: report_type)
              end

              message ||= format(described_class::DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, 25)

              expect_warning_or_error(report_type: report_type, message: message)
            end
          end

          context 'when fail on error is false and a custom message is given' do
            it_behaves_like 'reporting PR length check custom warnings or errors', false, 'this is my custom warning message'
          end

          context 'when fail on error is false' do
            it_behaves_like 'reporting PR length check custom warnings or errors', false
          end

          context 'when fail on error is true' do
            it_behaves_like 'reporting PR length check custom warnings or errors', true
          end

          context 'when a custom error message is given and fail on error is true' do
            it_behaves_like 'reporting PR length check custom warnings or errors', true, 'this is my custom error message'
          end
        end
      end

      def expect_warning_or_error(report_type:, message:)
        if report_type == :error
          expect(@dangerfile).to report_errors([message])
        elsif report_type == :warning
          expect(@dangerfile).to report_warnings([message])
        end
      end
    end
  end
end
