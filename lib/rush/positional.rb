# typed: true
# frozen_string_literal: true

require 'forwardable'

module Rush
  # The positional parameters $1..$n: a list of strings that `set` replaces,
  # `shift` drops the front of, and a function call brackets with #with so the
  # caller's are restored on return. Reads ($1, $#, $@, the for-loop word list)
  # delegate to the underlying array.
  class Positional
    extend T::Sig
    extend Forwardable

    def_delegators :@values, :==, :[], :size, :empty?, :join, :map, :each, :to_a

    sig { params(values: T::Array[String]).void }
    def initialize(values = [])
      @values = values
    end

    sig { params(values: T::Array[String]).void }
    def replace(values)
      @values = values
    end

    sig { params(count: Integer).void }
    def shift(count)
      @values = @values.drop(count)
    end

    sig do
      type_parameters(:U)
        .params(values: T::Array[String], blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with(values, &blk)
      saved = T.let(@values, T::Array[String])
      @values = values
      yield
    ensure
      @values = T.must(saved)
    end
  end
end
