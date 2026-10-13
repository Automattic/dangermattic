# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::DependabotAutoMerger do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      let(:api) { instance_double(Octokit::Client) }
      let(:pr_json) do
        {
          'number' => 42,
          'node_id' => 'PR_kwDOABCD',
          'base' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } },
          'head' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } }
        }
      end
      let(:commit_message) { dependabot_commit(['okhttp'], 'version-update:semver-patch') }

      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.dependabot_auto_merger

        allow(@plugin.github).to receive_messages(pr_author: 'dependabot[bot]', api: api, pr_json: pr_json)
        allow(api).to receive_messages(
          user: { login: 'dangermattic[bot]' },
          pull_request_reviews: [],
          pull_request_commits: [{ commit: { message: commit_message } }],
          create_pull_request_review: nil,
          post: { data: {} }
        )
      end

      # Mirrors the YAML document Dependabot appends to its commit message, terminator and sign-off included.
      def dependabot_commit(names, update_type)
        entries = names.map do |name|
          "- dependency-name: #{name}\n  dependency-type: direct:production\n  update-type: #{update_type}\n"
        end

        <<~MESSAGE
          Bump #{names.join(' and ')}

          ---
          updated-dependencies:
          #{entries.join}...

          Signed-off-by: dependabot[bot] <support@github.com>
        MESSAGE
      end

      describe '#updated_dependencies' do
        context 'with a real grouped update captured from Dependabot' do
          let(:commit_message) { fixture('dependabot', 'grouped_minor_update.txt') }

          it 'reads every dependency out of the commit message' do
            expect(@plugin.updated_dependencies.map { |dependency| dependency['dependency-name'] })
              .to eq(['com.stripe:stripeterminal-taptopay', 'com.stripe:stripeterminal-core', 'com.stripe:stripeterminal-ktx'])
          end

          it 'reads the update type' do
            expect(@plugin.updated_dependencies.map { |dependency| dependency['update-type'] }.uniq).to eq(['version-update:semver-minor'])
          end
        end

        context 'when the commit carries no Dependabot metadata' do
          let(:commit_message) { 'Bump okhttp from 1.0.0 to 1.0.1' }

          it 'reports no dependencies' do
            expect(@plugin.updated_dependencies).to be_empty
          end
        end
      end

      describe '#auto_merge_patch_updates' do
        context 'with a patch update' do
          it 'approves the pull request, saying why' do
            @plugin.auto_merge_patch_updates

            expect(api).to have_received(:create_pull_request_review)
              .with('Automattic/dangermattic', 42, hash_including(event: 'APPROVE', body: a_string_including('all updates are patch level.')))
          end

          it 'enables auto-merge through the GraphQL mutation' do
            @plugin.auto_merge_patch_updates

            expect(api).to have_received(:post).with('/graphql', a_string_including('enablePullRequestAutoMerge'))
          end

          it 'passes the pull request node id and merge method to the mutation' do
            @plugin.auto_merge_patch_updates(merge_method: 'SQUASH')

            expect(api).to have_received(:post).with('/graphql', a_string_including('"pullRequestId":"PR_kwDOABCD"', '"mergeMethod":"SQUASH"'))
          end

          it 'returns the reason it enabled auto-merge' do
            expect(@plugin.auto_merge_patch_updates).to eq('all updates are patch level.')
          end
        end

        context 'when the pull request is already approved by this account' do
          before do
            allow(api).to receive(:pull_request_reviews).and_return(
              [{ state: 'APPROVED', user: { login: 'dangermattic[bot]' } }]
            )
          end

          # Danger reruns on `labeled`, `synchronize` and friends, none of which should trigger a second review.
          it 'does not approve a second time' do
            @plugin.auto_merge_patch_updates

            expect(api).not_to have_received(:create_pull_request_review)
          end

          it 'still enables auto-merge, which is idempotent' do
            @plugin.auto_merge_patch_updates

            expect(api).to have_received(:post)
          end
        end

        context 'when somebody else approved the pull request' do
          before do
            allow(api).to receive(:pull_request_reviews).and_return(
              [{ state: 'APPROVED', user: { login: 'mokagio' } }]
            )
          end

          it 'still leaves its own approval' do
            @plugin.auto_merge_patch_updates

            expect(api).to have_received(:create_pull_request_review)
          end
        end

        context 'with a minor update' do
          let(:commit_message) { dependabot_commit(['release-toolkit'], 'version-update:semver-minor') }

          it 'does nothing by default' do
            expect(@plugin.auto_merge_patch_updates).to be_nil
          end

          it 'auto-merges an allowlisted dependency' do
            expect(@plugin.auto_merge_patch_updates(minor_update_allowlist: ['release-toolkit'])).to eq('every dependency in this minor update is on the allowlist.')
          end

          it 'says why it auto-merged an allowlisted dependency' do
            @plugin.auto_merge_patch_updates(minor_update_allowlist: ['release-toolkit'])

            expect(api).to have_received(:create_pull_request_review)
              .with(anything, anything, hash_including(body: a_string_including('on the allowlist.')))
          end
        end

        context 'with a major update' do
          let(:commit_message) { dependabot_commit(['okhttp'], 'version-update:semver-major') }

          it 'does nothing, even for an allowlisted dependency' do
            expect(@plugin.auto_merge_patch_updates(minor_update_allowlist: ['okhttp'])).to be_nil
          end
        end

        context 'with a grouped update' do
          let(:commit_message) { dependabot_commit(%w[okhttp retrofit], 'version-update:semver-patch') }

          it 'auto-merges when every dependency is a patch' do
            expect(@plugin.auto_merge_patch_updates).to eq('all updates are patch level.')
          end

          it 'does nothing when one dependency is denylisted' do
            expect(@plugin.auto_merge_patch_updates(denylist: ['retrofit'])).to be_nil
          end

          context 'with a minor bump' do
            let(:commit_message) { dependabot_commit(%w[okhttp retrofit], 'version-update:semver-minor') }

            it 'does nothing when only some dependencies are allowlisted' do
              expect(@plugin.auto_merge_patch_updates(minor_update_allowlist: ['okhttp'])).to be_nil
            end
          end
        end

        context 'with a denylisted dependency' do
          it 'does nothing, even on a patch update' do
            expect(@plugin.auto_merge_patch_updates(denylist: ['okhttp'])).to be_nil
          end

          it 'matches dependency names exactly rather than by prefix' do
            expect(@plugin.auto_merge_patch_updates(denylist: ['okhttp-urlconnection'])).to eq('all updates are patch level.')
          end

          it 'takes precedence over the minor update allowlist' do
            expect(@plugin.auto_merge_patch_updates(denylist: ['okhttp'], minor_update_allowlist: ['okhttp'])).to be_nil
          end
        end

        context 'when the pull request is not from Dependabot' do
          before { allow(@plugin.github).to receive(:pr_author).and_return('mokagio') }

          it 'does nothing' do
            expect(@plugin.auto_merge_patch_updates).to be_nil
          end
        end

        context 'when the pull request comes from a fork' do
          let(:pr_json) do
            super().merge('head' => { 'repo' => { 'full_name' => 'someone-else/dangermattic' } })
          end

          it 'does nothing' do
            expect(@plugin.auto_merge_patch_updates).to be_nil
          end
        end

        context 'with an unsupported merge method' do
          it 'raises rather than sending it to GitHub' do
            expect { @plugin.auto_merge_patch_updates(merge_method: 'FAST_FORWARD') }.to raise_error(ArgumentError, /MERGE, SQUASH, REBASE/)
          end
        end

        context 'when GitHub rejects the mutation' do
          before do
            allow(api).to receive(:post).and_return({ errors: [{ message: 'Auto-merge is not allowed for this repository' }] })
          end

          it 'surfaces the error rather than reporting success' do
            expect { @plugin.auto_merge_patch_updates }.to raise_error(/Auto-merge is not allowed/)
          end
        end
      end
    end
  end
end
