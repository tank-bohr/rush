# frozen_string_literal: true

require 'fiddle'

# Shared helpers for rush-vs-dash differential specs.
module DifferentialHarness
  # Keeps orphaned probe descendants reapable without changing their session.
  module ProbeSubreaper
    OPTION = 36
    TYPES = [Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG].freeze

    module_function

    def enable
      available? && call(1)
    end

    def disable
      call(0) if available?
    end

    def available?
      RUBY_PLATFORM.include?('linux') && !function.nil?
    end

    def call(value)
      function.call(OPTION, value, 0, 0, 0).zero?
    end

    def function
      @function ||= Fiddle::Function.new(Fiddle::Handle::DEFAULT['prctl'], TYPES, Fiddle::TYPE_INT)
    rescue Fiddle::DLError
      nil
    end
  end
end
