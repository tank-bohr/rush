# frozen_string_literal: true

require 'simplecov' # loads .simplecov and starts coverage before lib is required

require 'stringio'
require 'rush'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.include SegmentHelpers
  config.order = :random
  Kernel.srand(config.seed)
end
