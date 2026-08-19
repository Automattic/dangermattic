# Dangermattic
`Dangermattic` builds on [Danger on Ruby](https://danger.systems/ruby/) and is essentially a collection of Danger plugins. Its goal is to provide customisable checks and common utilities to help perform checks on Pull Requests, from simple routine validations to more sophisticated ones.

## Installation

Add to your project's `Gemfile`
```
gem 'danger-dangermattic', git: 'https://github.com/Automattic/dangermattic'
```

### Translation context plugin setup

Use source discovery when a project defines localization keys directly in source code, as is common on iOS:

```ruby
translation_context_checker.check_source_changes(
  source_paths: ['WooCommerce/', 'Modules/Sources/'],
  inline_mode: :source_suggestion
)
```

Use resource discovery when keys are added to a source-language localization file, as is common on Android:

```ruby
translation_context_checker.check_resource_changes(
  source_paths: ['app/src/main/java/'],
  resource_paths: ['app/src/main/res/values/strings.xml']
)
```

`source_paths` is the source-code search scope in both workflows. In a pull request that changes both source
calls and localization resources, call the checker once for each workflow if both sets of keys need context.

Anthropic is the default provider and reads `ANTHROPIC_API_KEY` from the environment. Pass `provider: :openai`
to use OpenAI with `OPENAI_API_KEY`. Store the matching key as a CI secret.

The checker posts inline comments by default. Use `inline_mode` for apply-ready suggestions or to disable inline
output, and `summary: true` for a pull-request summary. Optional `context_files` are included in full;
`include_pull_request_context: false` excludes the pull request title and description.

Relevant source snippets, context files, and pull request metadata are sent to the configured external LLM
provider. Enable the checker only for content that provider is permitted to process. Bundler installs the
required [`i18n-context-generator`](https://github.com/Automattic/i18n-context-generator) gem with Dangermattic;
see that project for supported source syntax and advanced generator behavior.

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
- `translation_context_checker` - Suggests translator-facing context for changed localization keys
    ```ruby
    # Suggests apply-ready comments for changed iOS localization calls
    translation_context_checker.check_source_changes(
      source_paths: ['WooCommerce/', 'Modules/Sources/'],
      inline_mode: :source_suggestion
    )
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

### How to verify a change against a real pull request

Unit tests are the main development loop, but before releasing a new or changed check it's often useful to see it run end-to-end against a real pull request.
You can do this locally with `danger pr`, which evaluates a `Dangerfile` against an existing PR's diff and prints the result to your terminal only, without posting upstream.

Point a `Gemfile` at your branch and add the check you want to exercise to a `Dangerfile`:

```ruby
# Gemfile
source 'https://rubygems.org'
gem 'danger-dangermattic', git: 'https://github.com/Automattic/dangermattic', branch: 'my-branch'
```

```ruby
# Dangerfile
my_new_plugin_checker.check_method
```

After a `bundle install`, run it against a PR from inside a checkout of that PR's repository:

```sh
DANGER_GITHUB_API_TOKEN="$(gh auth token)" \
  BUNDLE_GEMFILE=/path/to/Gemfile \
  bundle exec danger pr https://github.com/<org>/<repo>/pull/<number> \
  --dangerfile=/path/to/Dangerfile
```

A failure prints as an `Errors:` block. `danger pr` only fetches and creates temporary refs that it cleans up afterwards, so it won't change your current branch or working tree.
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
