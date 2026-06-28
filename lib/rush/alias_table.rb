# frozen_string_literal: true

module Rush
  # The shell's alias definitions: a name maps to the replacement text the lexer
  # splices in when the name appears in command position (POSIX 2.3.1). The
  # `alias` builtin validates names; the table just stores what it is given.
  class AliasTable
    def initialize
      @aliases = {}
    end

    def define(name, value)
      @aliases[name] = value
    end

    def remove(name)
      @aliases.delete(name)
    end

    def value(name)
      @aliases[name]
    end

    def key?(name)
      @aliases.key?(name)
    end

    def clear
      @aliases.clear
    end

    # name => value pairs sorted by name, for `alias` with no operands. dash lists
    # in hash order; rush sorts for a deterministic, testable listing.
    def listing
      @aliases.sort
    end
  end
end
