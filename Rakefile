# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task default: :all

desc 'Runs all tasks: :specs, :rubocop and :danger_lint'
task all: %i[specs lint]

desc 'Ensure that the plugin passes `danger plugins lint`'
task :danger_lint do
  sh('bundle', 'exec', 'danger', 'plugins', 'lint')
end

desc 'Runs linting tasks: :rubocop and :danger_lint'
task lint: %i[rubocop danger_lint]

desc 'Run Unit Tests'
RSpec::Core::RakeTask.new(:specs)

desc 'Run RuboCop on the lib/specs directory'
RuboCop::RakeTask.new(:rubocop)

desc 'Generate the docs using YARD'
task :doc do
  sh('yard', 'doc')
  # Open generated doc in browser
  sh('open', 'yard-doc/index.html')
end

desc "Print stats about undocumented methods. Provide an optional path relative to 'lib/dangermattic/plugins' to only show stats for that subdirectory"
task :docstats, [:path] do |_, args|
  path = File.join('lib/dangermattic/plugins', args[:path] || '.')
  sh('yard', 'stats', '--list-undoc', path)
end

VERSION_FILE = File.join('lib', 'dangermattic', 'gem_version.rb')

desc 'Create a new version of the dangermattic gem'
task :new_release do
  require_relative(VERSION_FILE)

  parser = ChangelogParser.new(file: 'CHANGELOG.md')
  latest_version = parser.parse_pending_section

  ## Print current info
  Console.header "Current version is: #{Dangermattic::VERSION}"
  Console.warning "Warning: Latest version number does not match latest version title in CHANGELOG (#{latest_version})!" unless latest_version == Dangermattic::VERSION

  Console.header 'Pending CHANGELOG:'
  changelog = parser.cleaned_pending_changelog_lines
  Console.print_indented_lines(changelog)

  ## Prompt for next version number
  guess = parser.guessed_next_semantic_version(current: Dangermattic::VERSION)
  new_version = Console.prompt('New version to release', guess)

  ## Checkout branch, update files
  GitHelper.check_or_create_branch(new_version)
  Console.header 'Update `VERSION` constant in `version.rb`...'
  update_version_constant(VERSION_FILE, new_version)
  Console.header 'Updating CHANGELOG...'
  parser.update_for_new_release(new_version: new_version)

  # Commit and push
  Console.header 'Commit and push changes...'
  GitHelper.commit_files("Bumped to version #{new_version}", [VERSION_FILE, 'Gemfile.lock', 'CHANGELOG.md'])

  Console.header 'Opening PR draft in your default browser...'
  pr_body = <<~BODY
    Releasing new version #{new_version}.

    # What's Next

    PR Author: Be sure to create and publish a GitHub Release pointing to `trunk` once this PR gets merged,
    copy/pasting the following text as the GitHub Release's description:
    ```
    #{changelog.join}
    ```
  BODY
  GitHelper.prepare_github_pr("release/#{new_version}", 'trunk', "Release #{new_version} into trunk", pr_body)

  Console.info <<~INSTRUCTIONS

    ---------------

    >>> WHAT'S NEXT

    Once the PR is merged, publish a GitHub release for `#{new_version}`, targeting `trunk`,
    with the following text as description:

    ```
    #{changelog.join}
    ```

    The publication of the new GitHub release will create a git tag, which in turn will trigger
    a CI workflow that will take care of doing the `gem push` of the new version to RubyGems.

  INSTRUCTIONS
end

def update_version_constant(version_file, new_version)
  content = File.read(version_file)
  content.gsub!(/VERSION = .*/, "VERSION = '#{new_version}'")
  File.write(version_file, content)

  # Updates the Gemfile.lock with the new dangermattic version
  sh('bundle', 'install', '--quiet')
end
