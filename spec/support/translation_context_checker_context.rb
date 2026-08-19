# frozen_string_literal: true

# The existing specs use these fixture objects across nested contexts.
# rubocop:disable RSpec/InstanceVariable
RSpec.shared_context 'with translation context checker' do
  before do
    @dangerfile = testing_dangerfile
    @plugin = @dangerfile.translation_context_checker

    allow(@plugin.git).to receive_messages(added_files: [], modified_files: [], deleted_files: [])
    allow(@plugin.github).to receive_messages(pr_title: '', pr_body: '')
    allow(@plugin).to receive(:validate_configured_paths).and_return(nil)
    allow(I18nContextGenerator::GitDiff).to receive(:new).and_wrap_original do |constructor, *args, **kwargs|
      git_diff = constructor.call(*args, **kwargs)
      allow(git_diff).to receive(:git_diff_for_path) do |path|
        @plugin.danger.git.diff_for_file(path)&.patch.to_s
      end
      git_diff
    end
    stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
    extraction_result_class = Struct.new(
      :key, :text, :description, :source_file, :ui_element, :tone, :max_length, :locations,
      :changed_locations, :changed_location_groups, :translation_key,
      :changed_translation_locations, :status, :error,
      keyword_init: true
    ) do
      def actionable?
        status == :success && error.nil? && !description.to_s.strip.empty?
      end
    end
    stub_const('ExtractionResultStruct', extraction_result_class)
  end

  def build_extraction_result(**overrides)
    ExtractionResultStruct.new(
      {
        key: 'default_key',
        text: 'Default text',
        description: 'Default description',
        source_file: nil,
        ui_element: nil,
        tone: nil,
        max_length: nil,
        locations: [],
        changed_locations: [],
        changed_location_groups: [],
        translation_key: 'default_key',
        changed_translation_locations: [],
        status: :success,
        error: nil
      }.merge(overrides)
    )
  end

  def expect_no_danger_output
    expect(@dangerfile).to not_report
  end

  def status_markdowns
    @dangerfile.status_report[:markdowns]
  end

  def strings_diff(path, added_line:, start_line: 1)
    <<~DIFF
      diff --git a/#{path} b/#{path}
      --- a/#{path}
      +++ b/#{path}
      @@ -#{start_line},1 +#{start_line},2 @@
       "Existing" = "Existing";
      +#{added_line}
    DIFF
  end

  def added_file_diff(path, lines)
    <<~DIFF + lines.map { |line| "+#{line}" }.join
      diff --git a/#{path} b/#{path}
      --- /dev/null
      +++ b/#{path}
      @@ -0,0 +1,#{lines.length} @@
    DIFF
  end

  def stub_xcstrings_catalog(path, lines, patch: added_file_diff(path, lines))
    allow(File).to receive(:exist?).with(path).and_return(true)
    allow(File).to receive(:readlines).with(path).and_return(lines)
    allow(@plugin).to receive(:build_added_line_map).and_call_original
    allow(@plugin.danger.git).to receive(:diff_for_file).with(path).and_return(
      GitDiffStruct.new('modified', path, patch)
    )
  end

  def post_xcstrings_suggestion(path, description:, lines: [3])
    result = build_extraction_result(
      key: 'settings.title',
      description: description,
      changed_translation_locations: lines.map do |line|
        I18nContextGenerator::ChangedLocation.new(
          file: path,
          line: line,
          side: :right
        )
      end
    )

    @plugin.send(
      :post_inline_comments,
      [result],
      :message,
      inline_mode: :resource_suggestion
    )

    status_markdowns.fetch(0)
  end

  def parse_applied_suggestion(lines, markdown)
    match = markdown.message.match(/\A```suggestion\n(?<replacement>.*)\n```\z/m)
    raise 'Expected a GitHub suggestion block' unless match

    updated = lines.dup
    first_line = (markdown.start_line || markdown.line) - 1
    last_line = markdown.line - 1
    replacement = match[:replacement].lines(chomp: true).map { |line| "#{line}\n" }
    updated[first_line..last_line] = replacement
    JSON.parse(updated.join)
  end
end
# rubocop:enable RSpec/InstanceVariable
