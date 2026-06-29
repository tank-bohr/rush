# frozen_string_literal: true

require 'simplecov' # loads .simplecov and starts coverage before lib is required

require 'stringio'
require 'rush'

# sorbet-runtime validates the inline `sig {}` types at call time, but this suite
# injects RSpec verifying doubles (instance_double) that satisfy an interface
# without being `is_a?` the declared class. The static `srb tc` gate already covers
# types; production keeps runtime validation (a capability RBS/Steep lacks), but in
# tests a sig "violation" is a double, not a bug — so let it through.
T::Configuration.call_validation_error_handler = ->(_signature, _opts) {}

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.include SegmentHelpers
  config.order = :random
  Kernel.srand(config.seed)
end
