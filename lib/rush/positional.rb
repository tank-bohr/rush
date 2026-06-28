# frozen_string_literal: true

require 'forwardable'

module Rush
  # The positional parameters $1..$n: a list of strings that `set` replaces,
  # `shift` drops the front of, and a function call brackets with #with so the
  # caller's are restored on return. Reads ($1, $#, $@, the for-loop word list)
  # delegate to the underlying array.
  class Positional
    extend Forwardable

    def_delegators :@values, :==, :[], :size, :empty?, :join, :map, :each, :to_a

    def initialize(values = [])
      @values = values
    end

    def replace(values)
      @values = values
    end

    def shift(count)
      @values = @values.drop(count)
    end

    def with(values)
      saved = @values
      @values = values
      yield
    ensure
      @values = saved
    end
  end
end
