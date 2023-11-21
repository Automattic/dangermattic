# frozen_string_literal: true

Dir[File.join(__dir__, 'dangermattic/plugins', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'dangermattic/plugins/common', '*.rb')].each { |file| require file }
