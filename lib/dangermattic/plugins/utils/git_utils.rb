# frozen_string_literal: true

class GitUtils
  def self.android_test_file?(path:)
    path.match? %r{/(test|androidTest).*\.(java|kt)$}
  end

  def self.ios_test_file?(path:)
    path.match? %r{^(?:.*/)?\w+Tests?\.(swift|m)$}
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
end
