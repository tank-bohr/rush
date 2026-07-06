# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Resolves a parameter name through ShellState's parameter namespace. The
    # shell state owns variables, special parameters and positionals, including
    # the original shell pid exposed through $$.
    class Resolver
      extend T::Sig

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def resolve(name)
        @executor.state.parameters.resolve(name)
      end
    end
  end
end
