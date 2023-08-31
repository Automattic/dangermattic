# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task default: :all

desc 'Runs all tasks: :specs, :rubocop and :danger_lint'
task all: %i[specs lint]

desc 'Ensure that the plugin passes `danger plugins lint`'
task :danger_lint do
  sh 'bundle exec danger plugins lint'
end

desc 'Runs linting tasks: :rubocop and :danger_lint'
task lint: %i[rubocop danger_lint]

desc 'Run Unit Tests'
RSpec::Core::RakeTask.new(:specs)

desc 'Run RuboCop on the lib/specs directory'
RuboCop::RakeTask.new(:rubocop)
