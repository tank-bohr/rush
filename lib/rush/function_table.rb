# frozen_string_literal: true

module Rush
  # Name -> function body (an AST node), defined by function definitions and
  # looked up during command dispatch.
  class FunctionTable
    def initialize = @functions = {}

    def define(name, body) = @functions[name] = body

    def fetch(name) = @functions[name]

    def key?(name) = @functions.key?(name)
  end
end
