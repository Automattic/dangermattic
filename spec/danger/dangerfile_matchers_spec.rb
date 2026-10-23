# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'not_report matcher' do # rubocop:disable RSpec/DescribeClass
  it 'treats absent report collections as empty' do
    dangerfile = Struct.new(:status_report).new({})

    expect(dangerfile).to not_report
  end
end
