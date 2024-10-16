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

def fixture(name)
  File.read("spec/fixtures/#{name}")
end

# custom matchers

RSpec::Matchers.define :report_warnings do |expected_warnings|
  match do |dangerfile|
    dangerfile.status_report[:warnings].eql?(expected_warnings) &&
      dangerfile.status_report[:errors]&.empty? &&
      dangerfile.status_report[:messages]&.empty?
  end

  failure_message do |dangerfile|
    "expected warnings '#{expected_warnings}' to be reported, got instead:\n- Warnings: #{dangerfile.status_report[:warnings]}\n- Errors: #{dangerfile.status_report[:errors]}\n- Messages: #{dangerfile.status_report[:messages]}"
  end
end

RSpec::Matchers.define :report_errors do |expected_errors|
  match do |dangerfile|
    dangerfile.status_report[:errors].eql?(expected_errors) &&
      dangerfile.status_report[:warnings]&.empty? &&
      dangerfile.status_report[:messages]&.empty?
  end

  failure_message do |dangerfile|
    "expected errors '#{expected_errors}' to be reported, got instead:\n- Errors: #{dangerfile.status_report[:errors]}\n- Warnings: #{dangerfile.status_report[:warnings]}\n- Messages: #{dangerfile.status_report[:messages]}"
  end
end

RSpec::Matchers.define :report_messages do |expected_messages|
  match do |dangerfile|
    dangerfile.status_report[:messages].eql?(expected_messages) &&
      dangerfile.status_report[:errors]&.empty? &&
      dangerfile.status_report[:warnings]&.empty?
  end

  failure_message do |dangerfile|
    "expected messages '#{expected_messages}' to be reported, got instead:\n- Messages: #{dangerfile.status_report[:messages]}\n- Warnings: #{dangerfile.status_report[:warnings]}\n- Errors: #{dangerfile.status_report[:errors]}"
  end
end

RSpec::Matchers.define :not_report do
  match do |dangerfile|
    dangerfile.status_report[:errors]&.empty? &&
      dangerfile.status_report[:warnings]&.empty? &&
      dangerfile.status_report[:messages]&.empty?
  end

  failure_message do |dangerfile|
    "expected no warnings or errors to be reported, got instead:\n#{dangerfile.status_report}"
  end
end
