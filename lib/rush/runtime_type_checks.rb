# typed: true
# frozen_string_literal: true

require 'sorbet-runtime'

module Rush
  # Production policy for Sorbet's runtime method wrappers. This bootstrapping
  # method deliberately has no runtime sig: its body must run before any sig
  # block evaluates. Static Sorbet and Steep still check this source normally.
  module RuntimeTypeChecks
    def self.configure
      level = ENV.fetch('RUSH_RUNTIME_TYPECHECKS', nil) == '1' ? :always : :never
      T::Configuration.default_checked_level = level
    end
  end
end
