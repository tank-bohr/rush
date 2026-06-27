# frozen_string_literal: true

module Rush
  # The shell's alias definitions: a name maps to the replacement text the lexer
  # splices in when the name appears in command position (POSIX 2.3.1). The
  # `alias` builtin validates names; the table just stores what it is given.
  class AliasTable
    def initialize = @aliases = {}

    def define(name, value) = @aliases[name] = value

    def remove(name) = @aliases.delete(name)

    def value(name) = @aliases[name]

    def key?(name) = @aliases.key?(name)

    def clear = @aliases.clear

    # name => value pairs sorted by name, for `alias` with no operands. dash lists
    # in hash order; rush sorts for a deterministic, testable listing.
    def listing = @aliases.sort
  end
end
