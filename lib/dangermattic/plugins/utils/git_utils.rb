# frozen_string_literal: true

# Class with utility methods related to git
class GitUtils
  def self.change_type(diff_line:)
    if diff_line.start_with?('+') && !diff_line.start_with?('+++ ')
      :added
    elsif diff_line.start_with?('-') && !diff_line.start_with?('--- ')
      :removed
    else
      :other
    end
  end
end
