# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Registry of ${} operator forms keyed by the operator character. Each form
    # is given a ParameterExpander and returns quote-aware field parts. The ':'
    # variants treat a null value like an unset one (ParameterExpander#unset_or_null?).
    module Parameter
      # '-' use default · '=' assign default · '?' error if unset · '+' use alternative
      # The #: types each lambda's parameter: Steep does not propagate a frozen
      # hash's declared value type into bare `->(param)` literals (it would for an
      # un-frozen literal), so the param stays untyped without the annotation.
      FORMS = {
        '-' => ->(param) { param.unset_or_null? ? param.arg_parts : param.value_parts }, #: ^(ParameterExpander) -> Array[FieldPart]
        '=' => ->(param) { param.unset_or_null? ? param.assign_parts : param.value_parts }, #: ^(ParameterExpander) -> Array[FieldPart]
        '?' => ->(param) { param.unset_or_null? ? param.raise_unset : param.value_parts }, #: ^(ParameterExpander) -> Array[FieldPart]
        '+' => ->(param) { param.unset_or_null? ? param.empty_parts : param.arg_parts } #: ^(ParameterExpander) -> Array[FieldPart]
      }.freeze
    end
  end
end
