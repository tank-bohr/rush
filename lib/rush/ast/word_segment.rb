# frozen_string_literal: true

module Rush
  module AST
    # A typed piece of a word that preserves quote provenance for the expander.
    # Phase 0 only produces :literal; :single/:double/:param/:cmd_sub/:arith/:tilde
    # arrive with the real lexer and expander.
    WordSegment = Data.define(:kind, :text)
  end
end
