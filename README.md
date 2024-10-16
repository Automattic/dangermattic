# Dangermattic
`Dangermattic` builds on [Danger on Ruby](https://danger.systems/ruby/) and is essentially a collection of Danger plugins. Its goal is to provide customisable checks and common utilities to help perform checks on Pull Requests, from simple routine validations to more sophisticated ones.

## Installation

Add to your project's `Gemfile`
```
gem 'danger-dangermattic', git: 'https://github.com/Automattic/dangermattic'
```

## Example of available plugins and their usage

Once the main Gem is installed, all Dangermattic plugins are available in your `Dangerfile` under their corresponding namespace. A few examples:

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
- `view_changes_checker` - Detects view changes in a PR and reports a warning if there are no attached screenshots
    ```ruby
    # Reports a warning if a pull request changing views doesn't have a screenshot
    view_changes_checker.check
    ```

All available plugins are defined here: https://github.com/Automattic/dangermattic/tree/trunk/lib/dangermattic/plugins

## GitHub Workflows

Dangermattic also provides some useful reusable GitHub workflows. For more information on available workflows and how to use them, please refer to the [Workflows README](.github/workflows/README.md).

## Development

- Clone the repo and run `bundle install` to setup dependencies
- Run `bundle exec rake` to run the all the tests, RuboCop and Danger Lint
- Run `bundle exec rake specs` / `bundle exec rspec` to run only the unit tests
- Run `bundle exec rake lint` to run only the linting tasks: RuboCop and Danger Lint
- Use `bundle exec guard` to automatically have tests run as you make changes.
- You can generate the documentation using `bundle exec yard doc`. The documentation is generated locally in the `yard-doc/` folder.

### Adding a new plugin

Adding a new plugin to Dangermattic is very simple: just create a new subclass of `Danger::Plugin` inside `./lib/dangermattic/plugins/`, similarly to the other classes you'll find there:

```ruby
module Danger
  class MyNewPluginChecker < Plugin
    def check_method(param:)
      # ...
    end
  end
end
```

It will be [automatically imported](https://github.com/Automattic/dangermattic/blob/trunk/lib/danger_plugin.rb), exposed by Dangermattic's Gem and visible in your `Dangerfile` once you add it as a dependency:

```ruby
# In a Dangerfile
my_new_plugin_checker.check_method(param: my_param_value)
```

Please follow the existing naming convention for validation and check plugins: classes end with a `*Checker` suffix and the main validation methods are named with a `check_*` prefix.

## Releasing a new version

To create a new release of the Dangermattic gem, use the `new_release` Rake task:

```
bundle exec rake new_release
```

This task will:

1. Parse the `CHANGELOG.md` file to get the latest version and pending changes.
1. Prompt for the new version number.
1. Update the `VERSION` constant in the `gem_version.rb` file.
1. Update the `CHANGELOG.md` file with the new version.
1. Create a new branch, commit the changes, and push to GitHub.
1. Open a draft Pull Request for the release.

After running the task, follow the instructions provided to complete the release process:

1. Review and merge the Pull Request.
1. Create a GitHub release targeting the `trunk` branch, using the changelog content provided.
1. Publishing the GitHub release with a tag will trigger a CI workflow to publish the new gem version to RubyGems.
