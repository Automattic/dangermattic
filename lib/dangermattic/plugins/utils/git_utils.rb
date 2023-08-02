# frozen_string_literal: true

# Class with utility methods related to git
class GitUtils
  def self.added_lines(diff_patch:)
    select_lines(diff_patch: diff_patch, change_type: :added)
  end

  def self.removed_lines(diff_patch:)
    select_lines(diff_patch: diff_patch, change_type: :removed)
  end

  def self.change_type(diff_line:)
    if diff_line.start_with?('+') && !diff_line.start_with?('+++ ')
      :added
    elsif diff_line.start_with?('-') && !diff_line.start_with?('--- ')
      :removed
    else
      :other
    end
  end

  def self.select_lines(diff_patch:, change_type:)
    selected_lines = diff_patch.lines.select { |line| change_type(diff_line: line) == change_type }
    selected_lines.map { |line| line[1..] }.join
  end
end
