# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # Base for every AST node. Subclasses implement #execute(executor) so the
    # executor dispatches polymorphically and never switches on node type.
    class Node
      def execute(_executor)
        raise NotImplementedError
      end
    end
  end
end
