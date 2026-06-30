# typed: true
# frozen_string_literal: true

module Rush
  # Name -> function body (an AST node), defined by function definitions and
  # looked up during command dispatch.
  class FunctionTable
    extend T::Sig

    sig { void }
    def initialize
      @functions = {}
    end

    sig { params(name: String, body: AST::Node).returns(AST::Node) }
    def define(name, body)
      @functions[name] = body
    end

    sig { params(name: String).returns(T.nilable(AST::Node)) }
    def undefine(name)
      @functions.delete(name)
    end

    sig { params(name: String).returns(AST::Node) }
    def fetch(name)
      @functions.fetch(name)
    end

    sig { params(name: String).returns(T::Boolean) }
    def key?(name)
      @functions.key?(name)
    end
  end
end
