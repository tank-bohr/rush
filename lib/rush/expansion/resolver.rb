# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Resolves a parameter name through ShellState's parameter namespace. The
    # shell state owns variables, special parameters and positionals; the
    # executor supplies process-specific data such as $$.
    class Resolver
      extend T::Sig

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def resolve(name)
        pid = name == '$' ? @executor.system.pid : 0
        @executor.state.parameters.resolve(name, pid: pid)
      end
    end
  end
end
