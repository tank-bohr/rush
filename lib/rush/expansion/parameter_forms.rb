# frozen_string_literal: true

module Rush
  module Expansion
    # Registry of ${} operator forms keyed by the operator character. Each form
    # is given a ParameterExpander and returns the expanded string. The ':'
    # variants treat a null value like an unset one (ParameterExpander#unset_or_null?).
    module Parameter
      # '-' use default · '=' assign default · '?' error if unset · '+' use alternative
      # The #: types each lambda's parameter: Steep does not propagate a frozen
      # hash's declared value type into bare `->(param)` literals (it would for an
      # un-frozen literal), so the param stays untyped without the annotation.
      FORMS = {
        '-' => ->(param) { param.unset_or_null? ? param.arg : param.value.to_s }, #: ^(ParameterExpander) -> String
        '=' => ->(param) { param.unset_or_null? ? param.assign(param.arg) : param.value.to_s }, #: ^(ParameterExpander) -> String
        '?' => ->(param) { param.unset_or_null? ? param.raise_unset : param.value.to_s }, #: ^(ParameterExpander) -> String
        '+' => ->(param) { param.unset_or_null? ? '' : param.arg } #: ^(ParameterExpander) -> String
      }.freeze
    end
  end
end
