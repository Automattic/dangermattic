# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Danger::Dangerfile do
  it 'treats absent report collections as empty' do
    dangerfile = Struct.new(:status_report).new({})

    expect(dangerfile).to not_report
  end
end
