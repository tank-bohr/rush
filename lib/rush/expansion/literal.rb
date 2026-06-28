# frozen_string_literal: true

module Rush
  module Expansion
    # Expands a literal word segment: the text is already final (quotes were
    # removed at lex time), so it is returned verbatim. The identity expander
    # that lets every segment kind share one (executor, value) -> #expand seam.
    class Literal
      def initialize(_executor, value)
        @value = value
      end

      def expand = @value
    end
  end
end
