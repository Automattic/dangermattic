# Dangermattic
`Dangermattic` builds on [Danger on Ruby](https://danger.systems/ruby/) and is essentially a collection of Danger plugins. Its goal is to provide customisable checks and common utilities to help perform checks on Pull Requests, from simple routine validations to more sophisticated ones.

## Installation

Add to your project's `Gemfile`
```
gem 'danger-dangermattic', git: 'https://github.com/Automattic/dangermattic'
```

## Available plugins and their usage

Once the main Gem is installed, all Dangermattic plugins are available in your `Dangerfile` under their corresponding namespace:

- `manifest_pr_checker` - Plugin to check if changes on a manifest file (i.e. `Gemfile`, `Podfile`) has a corresponding change in a lock file (i.e. `Gemfile.lock`, `Podfile.lock`)
```ruby
# Reports a warning if the Gemfile was changed but the Gemfile.lock wasn't
manifest_pr_checker.check_gemfile_lock_updated
```
- `milestone_checker` - Plugin for performing checks on a milestone associated with a pull request
```ruby
# Checks if the pull request's milestone is due in 3 days or less, reporting a warning if that's the case
milestone_checker.check_milestone_due_date(days_before_due: 3)
```
- `pr_size_checker` - Plugin to check the size of a Pull Request content and text body
```ruby
# Reports a warning if a pull request diff size is greater than 300
pr_size_checker.check_diff_size(max_size: 300)
```
- `view_changes_need_screenshots` - Detects view changes in a PR and reports a warning if there are no attached screenshots
```ruby
# Reports a warning if a pull request changing views doesn't have a screenshot
view_changes_need_screenshots.view_changes_need_screenshots
```

## Development

- Clone the repo and run `bundle install` to setup dependencies
- Run `bundle exec rake spec` to run the all the tests, RuboCop and Danger Lint
- Run `bundle exec rspec` to run the all unit tests
- Use `bundle exec guard` to automatically have tests run as you make changes.
- You can generate the documentation using `bundle exec yard doc`. The documentation is generated locally in the `yard-doc/` folder.
