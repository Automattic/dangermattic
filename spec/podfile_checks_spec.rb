# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::PodfileChecks do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.podfile_checks

        allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])

        stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
      end

      context 'when checking the entire Podfile.lock file' do
        it 'returns an error when there is a podfile dependency reference to a commit' do
          podfile_lock_content = <<~CONTENT
            PODS:
              - Kingfisher (7.8.1)
              - SwiftGen (6.5.1)
              - SwiftLint (0.49.1)

            DEPENDENCIES:
              - Kingfisher (from `https://github.com/onevcat/Kingfisher.git`, commit `c1f60c63f356d364f4284ba82961acbe7de79bcc`)
              - SwiftGen (~> 6.0)
              - SwiftLint (~> 0.49)

            SPEC REPOS:
              trunk:
              - SwiftGen
              - SwiftLint

            EXTERNAL SOURCES:
              Kingfisher:
              :commit: c1f60c63f356d364f4284ba82961acbe7de79bcc
              :git: https://github.com/onevcat/Kingfisher.git

            CHECKOUT OPTIONS:
              Kingfisher:
              :commit: c1f60c63f356d364f4284ba82961acbe7de79bcc
              :git: https://github.com/onevcat/Kingfisher.git

            SPEC CHECKSUMS:
              Kingfisher: 63f677311d36a3473f6b978584f8a3845d023dc5
              SwiftGen: a6d22010845f08fe18fbdf3a07a8e380fd22e0ea
              SwiftLint: 32ee33ded0636d0905ef6911b2b67bbaeeedafa5

            PODFILE CHECKSUM: 58bea7d9e64aa93550617dd989b9e5ceed3df3f4

            COCOAPODS: 1.12.1
          CONTENT

          allow(File).to receive(:read).with('./Podfile.lock').and_return(podfile_lock_content)

          @plugin.check_podfile_does_not_have_commit_references

          expected_message = "Podfile reference(s) to a commit hash:\n```Kingfisher (from `https://github.com/onevcat/Kingfisher.git`, commit `c1f60c63f356d364f4284ba82961acbe7de79bcc`)```"
          expect(@dangerfile.status_report[:errors]).to eq [expected_message]
        end

        it 'returns the right errors when there are multiple podfile dependencies referencing a commit' do
          podfile_lock_content = <<~CONTENT
            PODS:
            - Kingfisher (7.8.1)
            - SwiftGen (6.6.1)
            - SwiftLint (0.50.1)

            DEPENDENCIES:
              - Kingfisher (from `https://github.com/onevcat/Kingfisher.git`, commit `c1f60c63f356d364f4284ba82961acbe7de79bcc`)
              - SwiftGen (from `https://github.com/SwiftGen/SwiftGen.git`, commit `759cc111dfdc01dd8d66edf20ff88402b0978591`)
              - SwiftLint (from `https://github.com/realm/SwiftLint.git`, commit `28a4aa2`)

            EXTERNAL SOURCES:
              Kingfisher:
                :commit: c1f60c63f356d364f4284ba82961acbe7de79bcc
                :git: https://github.com/onevcat/Kingfisher.git
              SwiftGen:
                :commit: 759cc111dfdc01dd8d66edf20ff88402b0978591
                :git: https://github.com/SwiftGen/SwiftGen.git
              SwiftLint:
                :commit: 28a4aa2
                :git: https://github.com/realm/SwiftLint.git

            CHECKOUT OPTIONS:
              Kingfisher:
                :commit: c1f60c63f356d364f4284ba82961acbe7de79bcc
                :git: https://github.com/onevcat/Kingfisher.git
              SwiftGen:
                :commit: 759cc111dfdc01dd8d66edf20ff88402b0978591
                :git: https://github.com/SwiftGen/SwiftGen.git
              SwiftLint:
                :commit: 28a4aa2
                :git: https://github.com/realm/SwiftLint.git

            SPEC CHECKSUMS:
              Kingfisher: 63f677311d36a3473f6b978584f8a3845d023dc5
              SwiftGen: 787181d7895fa2f5e7313d05de92c387010149c2
              SwiftLint: 6b0cf1f4d619808dbc16e4fab064ce6fc79f090b

            PODFILE CHECKSUM: 33ada736a0466cd5db78f4a568b5cdafdeeddb22

            COCOAPODS: 1.12.1
          CONTENT

          allow(File).to receive(:read).with('./Podfile.lock').and_return(podfile_lock_content)

          @plugin.check_podfile_does_not_have_commit_references

          expected_message = <<~MESSAGE.chomp
            Podfile reference(s) to a commit hash:
            ```Kingfisher (from `https://github.com/onevcat/Kingfisher.git`, commit `c1f60c63f356d364f4284ba82961acbe7de79bcc`)
            SwiftGen (from `https://github.com/SwiftGen/SwiftGen.git`, commit `759cc111dfdc01dd8d66edf20ff88402b0978591`)
            SwiftLint (from `https://github.com/realm/SwiftLint.git`, commit `28a4aa2`)```
          MESSAGE
          expect(@dangerfile.status_report[:errors]).to eq [expected_message]
        end

        it 'returns no error when there are no Podfile dependencies reference to a commit' do
          podfile_lock_content = <<~CONTENT
            PODS:
              - SwiftGen (6.5.1)
              - SwiftLint (0.49.1)

            DEPENDENCIES:
              - SwiftGen (~> 6.0)
              - SwiftLint (~> 0.49)

            SPEC REPOS:
              trunk:
              - SwiftGen
              - SwiftLint

            SPEC CHECKSUMS:
              SwiftGen: a6d22010845f08fe18fbdf3a07a8e380fd22e0ea
              SwiftLint: 32ee33ded0636d0905ef6911b2b67bbaeeedafa5

            PODFILE CHECKSUM: 58bea7d9e64aa93550617dd989b9e5ceed3df3f4

            COCOAPODS: 1.12.1
          CONTENT

          allow(File).to receive(:read).with('./Podfile.lock').and_return(podfile_lock_content)

          @plugin.check_podfile_does_not_have_commit_references

          expect(@dangerfile.status_report[:errors]).to be_empty
        end
      end

      context 'when changing the Podfile.lock in a Pull Request' do
        it 'returns warnings when a PR adds pods pointing to a specific commit' do
          podfile_path = './path/to/podfile/Podfile.lock'
          allow(@plugin.git).to receive(:modified_files).and_return([podfile_path])

          podfile_lock_diff = <<~PODFILE
            diff --git a/Podfile.lock b/Podfile.lock
            index 4a47d5fc..d57533f5 100644
            --- a/Podfile.lock
            +++ b/Podfile.lock
            @@ -1,24 +1,38 @@
            PODS:
              - Kingfisher (7.8.1)
            -  - SwiftGen (6.6.2)
            -  - SwiftLint (0.51.0)
            +  - SwiftGen (6.6.1)
            +  - SwiftLint (0.50.1)

            DEPENDENCIES:
              - Kingfisher
            -  - SwiftGen
            -  - SwiftLint
            +  - SwiftGen (from `https://github.com/SwiftGen/SwiftGen.git`, commit `759cc111dfdc01dd8d66edf20ff88402b0978591`)
            +  - SwiftLint (from `https://github.com/realm/SwiftLint.git`, commit `28a4aa2`)

            SPEC REPOS:
              trunk:
                - Kingfisher
            -    - SwiftGen
            -    - SwiftLint
            +
            +EXTERNAL SOURCES:
            +  SwiftGen:
            +    :commit: 759cc111dfdc01dd8d66edf20ff88402b0978591
            +    :git: https://github.com/SwiftGen/SwiftGen.git
            +  SwiftLint:
            +    :commit: 28a4aa2
            +    :git: https://github.com/realm/SwiftLint.git
            +
            +CHECKOUT OPTIONS:
            +  SwiftGen:
            +    :commit: 759cc111dfdc01dd8d66edf20ff88402b0978591
            +    :git: https://github.com/SwiftGen/SwiftGen.git
            +  SwiftLint:
            +    :commit: 28a4aa2
            +    :git: https://github.com/realm/SwiftLint.git

            SPEC CHECKSUMS:
              Kingfisher: 63f677311d36a3473f6b978584f8a3845d023dc5
            -  SwiftGen: 1366a7f71aeef49954ca5a63ba4bef6b0f24138c
            -  SwiftLint: 1b7561918a19e23bfed960e40759086e70f4dba5
            +  SwiftGen: 787181d7895fa2f5e7313d05de92c387010149c2
            +  SwiftLint: 6b0cf1f4d619808dbc16e4fab064ce6fc79f090b

            -PODFILE CHECKSUM: 2c09a6c90634ae2e0afd8d992b96b06ae68cabc2
            +PODFILE CHECKSUM: 8dc39244eeee7e5d107d943a6269ca525115094b

            COCOAPODS: 1.12.1
          PODFILE

          diff = GitDiffStruct.new('modified', podfile_path, podfile_lock_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(podfile_path).and_return(diff)

          @plugin.check_podfile_diff_does_not_have_commit_references

          expected_warning = <<~WARNING
            This PR adds a Podfile reference to a commit hash:
            File `#{podfile_path}`:
            ```diff
            +  - SwiftGen (from `https://github.com/SwiftGen/SwiftGen.git`, commit `759cc111dfdc01dd8d66edf20ff88402b0978591`)
            ```
          WARNING

          expected_warning2 = <<~WARNING
            This PR adds a Podfile reference to a commit hash:
            File `#{podfile_path}`:
            ```diff
            +  - SwiftLint (from `https://github.com/realm/SwiftLint.git`, commit `28a4aa2`)
            ```
          WARNING

          expect(@dangerfile.status_report[:warnings]).to contain_exactly(expected_warning, expected_warning2)
        end

        it 'does nothing when a PR removes Podfile.lock commit references' do
          podfile_path = './path/to/podfile/Podfile.lock'
          allow(@plugin.git).to receive(:modified_files).and_return([podfile_path])

          podfile_lock_diff = <<~PODFILE
            diff --git a/Podfile.lock b/Podfile.lock
            index 369b66d6..4a47d5fc 100644
            --- a/Podfile.lock
            +++ b/Podfile.lock
            @@ -1,33 +1,24 @@
            PODS:
              - Kingfisher (7.8.1)
              - SwiftGen (6.6.2)
            -  - SwiftLint (0.50.1)
            +  - SwiftLint (0.51.0)

            DEPENDENCIES:
            -  - Kingfisher (>= 7.6.2, ~> 7.6)
            +  - Kingfisher
              - SwiftGen
            -  - SwiftLint (from `https://github.com/realm/SwiftLint.git`, commit `28a4aa2`)
            +  - SwiftLint

            SPEC REPOS:
              trunk:
                - Kingfisher
                - SwiftGen
            -
            -EXTERNAL SOURCES:
            -  SwiftLint:
            -    :commit: 28a4aa2
            -    :git: https://github.com/realm/SwiftLint.git
            -
            -CHECKOUT OPTIONS:
            -  SwiftLint:
            -    :commit: 28a4aa2
            -    :git: https://github.com/realm/SwiftLint.git
            +    - SwiftLint

            SPEC CHECKSUMS:
              Kingfisher: 63f677311d36a3473f6b978584f8a3845d023dc5
              SwiftGen: 1366a7f71aeef49954ca5a63ba4bef6b0f24138c
            -  SwiftLint: 6b0cf1f4d619808dbc16e4fab064ce6fc79f090b
            +  SwiftLint: 1b7561918a19e23bfed960e40759086e70f4dba5

            -PODFILE CHECKSUM: 7eea968a423d51c238de59edf2a857d882a9d762
            +PODFILE CHECKSUM: 2c09a6c90634ae2e0afd8d992b96b06ae68cabc2

            COCOAPODS: 1.12.1
          PODFILE

          diff = GitDiffStruct.new('modified', podfile_path, podfile_lock_diff)

          allow(@plugin.git).to receive(:diff_for_file).with(podfile_path).and_return(diff)

          @plugin.check_podfile_diff_does_not_have_commit_references

          expect(@dangerfile.status_report[:warnings]).to be_empty
        end
      end
    end
  end
end
