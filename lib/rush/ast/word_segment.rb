# frozen_string_literal: true

module Rush
  module AST
    # A typed piece of a word. `kind` is :literal for now (parameter, command,
    # arithmetic and tilde segments arrive in later slices). `value` is the text
    # with quotes already removed; `quoted` records whether it came from a quoted
    # context, which later governs field splitting and pathname expansion.
    WordSegment = Data.define(:kind, :value, :quoted)
  end
end
