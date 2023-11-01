# frozen_string_literal: true

Dir[File.join(__dir__, 'dangermattic/plugins', '*.rb')].each { |file| require file }

require 'dangermattic/plugins/common/git_utils'
