# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=value` — value is an unexpanded Word (it receives tilde and the
    # step-1 expansions, but no field splitting or pathname expansion).
    Assignment = Data.define(:name, :value)
  end
end
