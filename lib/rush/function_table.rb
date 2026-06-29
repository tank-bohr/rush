# typed: true
# frozen_string_literal: true

module Rush
  # Name -> function body (an AST node), defined by function definitions and
  # looked up during command dispatch.
  class FunctionTable
    def initialize
      @functions = {}
    end

    def define(name, body)
      @functions[name] = body
    end

    def undefine(name)
      @functions.delete(name)
    end

    def fetch(name)
      @functions.fetch(name)
    end

    def key?(name)
      @functions.key?(name)
    end
  end
end
