# frozen_string_literal: true

module Rush
  module AST
    # A typed piece of a word. `kind` is one of :literal, :param, :command or
    # :arith (tilde segments arrive in a later slice). `value` is the text with
    # quotes already removed; `quoted` records whether it came from a quoted
    # context, which later governs field splitting and pathname expansion.
    WordSegment = Data.define(:kind, :value, :quoted) do
      # Plain text the lexer can treat as a bare name (alias substitution, etc.):
      # a literal run that did not come from a quoted context.
      def literal_unquoted? = kind == :literal && !quoted
    end
  end
end
