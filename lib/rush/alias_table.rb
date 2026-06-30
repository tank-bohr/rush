# typed: true
# frozen_string_literal: true

module Rush
  # The shell's alias definitions: a name maps to the replacement text the lexer
  # splices in when the name appears in command position (POSIX 2.3.1). The
  # `alias` builtin validates names; the table just stores what it is given.
  class AliasTable
    extend T::Sig

    sig { void }
    def initialize
      @aliases = {}
    end

    sig { params(name: String, value: String).returns(String) }
    def define(name, value)
      @aliases[name] = value
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def remove(name)
      @aliases.delete(name)
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def value(name)
      @aliases[name]
    end

    sig { params(name: String).returns(T::Boolean) }
    def key?(name)
      @aliases.key?(name)
    end

    sig { void }
    def clear
      @aliases.clear
    end

    # name => value pairs sorted by name, for `alias` with no operands. dash lists
    # in hash order; rush sorts for a deterministic, testable listing.
    sig { returns(T::Array[[String, String]]) }
    def listing
      @aliases.sort
    end
  end
end
