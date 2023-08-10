# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'pry'

require 'rspec'
require 'danger'

if `git remote -v` == ''
  puts 'You cannot run tests without setting a local git remote on this repo'
  puts 'It\'s a weird side-effect of Danger\'s internals.'
  exit(0)
end

RSpec.configure do |config|
  config.filter_gems_from_backtrace 'bundler'
  config.color = true
  config.tty = true
end

require 'danger_plugin'

# These functions are a subset of https://github.com/danger/danger/blob/master/spec/spec_helper.rb
# If you are expanding these files, see if it's already been done ^.

# A silent version of the user interface,
# it comes with an extra function `.string` which will
# strip all ANSI colours from the string.

# rubocop:disable Lint/NestedMethodDefinition
def testing_ui
  @output = StringIO.new
  def @output.winsize
    [20, 9999]
  end

  cork = Cork::Board.new(out: @output)
  def cork.string
    out.string.gsub(/\e\[([;\d]+)?m/, '')
  end
  cork
end
# rubocop:enable Lint/NestedMethodDefinition

# Example environment (ENV)
def testing_env
  {
    'HAS_JOSH_K_SEAL_OF_APPROVAL' => 'true',
    'TRAVIS_PULL_REQUEST' => '800',
    'TRAVIS_REPO_SLUG' => 'artsy/eigen',
    'TRAVIS_COMMIT_RANGE' => '759adcbd0d8f...13c4dc8bb61d',
    'DANGER_GITHUB_API_TOKEN' => '123sbdq54erfsd3422gdfio'
  }
end

# A stubbed out Dangerfile for use in tests
def testing_dangerfile
  env = Danger::EnvironmentManager.new(testing_env)
  Danger::Dangerfile.new(env, testing_ui)
end

# custom matchers

RSpec::Matchers.define :report_warnings do |expected_warnings|
  match do |dangerfile|
    dangerfile.status_report[:warnings].eql?(expected_warnings) &&
      dangerfile.status_report[:errors]&.empty?
  end

  failure_message do |dangerfile|
    "expected warnings '#{expected_warnings}' to be reported, got instead:\n- Warnings: #{dangerfile.status_report[:warnings]}\n- Errors: #{dangerfile.status_report[:errors]}"
  end
end

RSpec::Matchers.define :report_errors do |expected_errors|
  match do |dangerfile|
    dangerfile.status_report[:errors].eql?(expected_errors) &&
      dangerfile.status_report[:warnings]&.empty?
  end

  failure_message do |dangerfile|
    "expected errors '#{expected_errors}' to be reported, got instead:\n- Errors: #{dangerfile.status_report[:errors]}\n- Warnings: #{dangerfile.status_report[:warnings]}"
  end
end

RSpec::Matchers.define :do_not_report do
  match do |dangerfile|
    dangerfile.status_report[:errors]&.empty? &&
      dangerfile.status_report[:warnings]&.empty?
  end

  failure_message do |dangerfile|
    "expected no warnings or errors to be reported, got instead:\n#{dangerfile.status_report}"
  end
end
