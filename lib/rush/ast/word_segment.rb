# frozen_string_literal: true

module Rush
  module AST
    # A typed piece of a word. `kind` is one of :literal, :param, :command or
    # :arith (tilde segments arrive in a later slice). `value` is the text with
    # quotes already removed; `quoted` records whether it came from a quoted
    # context, which later governs field splitting and pathname expansion.
    WordSegment = Data.define(:kind, :value, :quoted) do
      # This segment's text when it is plain enough to stand in as a bare name —
      # an unquoted literal run — else nil (a quoted or substitution segment).
      def literal_value = (value if kind == :literal && !quoted)
    end
  end
end
