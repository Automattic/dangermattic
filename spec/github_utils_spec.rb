# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::GithubUtils do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with the common_release_checker plugin' do
      let(:github) do
        instance_double(Danger::DangerfileGitHubPlugin, {
                          pr_json: {
                            'base' => { 'repo' => { 'full_name' => 'Automattic/dangermattic' } },
                            'number' => 42,
                            'requested_teams' => [],
                            'requested_reviewers' => []
                          },
                          api: instance_double(Octokit::Client),
                          branch_for_base: 'main',
                          pr_labels: [],
                          pr_title: 'Some PR Title'
                        })
      end

      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.github_utils

        allow(@plugin).to receive(:github).and_return(github)
      end

      describe '#active_reviewers?' do
        it 'returns true when there are active reviewers' do
          allow(github.api).to receive(:pull_request_reviews).and_return(%w[review1 review2])
          expect(@plugin.active_reviewers?).to be(true)
        end

        it 'returns false when there are no active reviewers' do
          allow(github.api).to receive(:pull_request_reviews).and_return([])
          expect(@plugin.active_reviewers?).to be(false)
        end
      end

      describe '#requested_reviewers?' do
        it 'returns true when there are requested reviewers' do
          allow(github.pr_json).to receive(:[]).with('requested_teams').and_return(['team1'])
          expect(@plugin.requested_reviewers?).to be(true)
        end

        it 'returns true when there are active reviewers' do
          allow(github.api).to receive(:pull_request_reviews).and_return(%w[review1 review2])
          expect(@plugin.requested_reviewers?).to be(true)
        end

        it 'returns false when there are no requested reviewers or active reviewers' do
          allow(github.api).to receive(:pull_request_reviews).and_return([])
          expect(@plugin.requested_reviewers?).to be(false)
        end
      end

      describe '#main_branch?' do
        it 'returns true when the branch is a main branch' do
          allow(github).to receive(:branch_for_base).and_return('develop')
          expect(@plugin.main_branch?).to be(true)
        end

        it 'returns false when the branch is not a main branch' do
          allow(github).to receive(:branch_for_base).and_return('feature-branch')
          expect(@plugin.main_branch?).to be(false)
        end
      end

      describe '#release_branch?' do
        it 'returns true when the branch is a release branch' do
          allow(github).to receive(:branch_for_base).and_return('release/30.6.0')
          expect(@plugin.release_branch?).to be(true)
        end

        it 'returns true when the branch is a hotfix branch' do
          allow(github).to receive(:branch_for_base).and_return('hotfix/fix-bug')
          expect(@plugin.release_branch?).to be(true)
        end

        it 'returns false when the branch is neither a release nor a hotfix branch' do
          allow(github).to receive(:branch_for_base).and_return('feature-branch')
          expect(@plugin.release_branch?).to be(false)
        end
      end

      describe '#wip_feature?' do
        it 'returns true when there is a WIP label' do
          allow(github).to receive(:pr_labels).and_return(['WIP'])
          expect(@plugin.wip_feature?).to be(true)
        end

        it 'returns true when there is WIP in the title' do
          allow(github).to receive(:pr_title).and_return('WIP: Some PR Title')
          expect(@plugin.wip_feature?).to be(true)
        end

        it 'returns false when there is no WIP label or WIP in the title' do
          allow(github).to receive_messages(pr_labels: [], pr_title: 'Some PR Title')
          expect(@plugin.wip_feature?).to be(false)
        end
      end
    end
  end
end
