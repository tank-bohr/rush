# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # Base for every AST node. Subclasses implement #execute(executor) so the
    # executor dispatches polymorphically and never switches on node type.
    class Node
      extend T::Sig

      sig { params(_executor: Executor).returns(Status) }
      def execute(_executor)
        raise NotImplementedError
      end
    end
  end
end
