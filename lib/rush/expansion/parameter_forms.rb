# frozen_string_literal: true

module Rush
  module Expansion
    # Registry of ${} operator forms keyed by the operator character. Each form
    # is given a ParameterExpander and returns the expanded string. The ':'
    # variants treat a null value like an unset one (ParameterExpander#unset_or_null?).
    module Parameter
      # '-' use default · '=' assign default · '?' error if unset · '+' use alternative
      FORMS = {
        '-' => ->(param) { param.unset_or_null? ? param.arg : param.value.to_s },
        '=' => ->(param) { param.unset_or_null? ? param.assign(param.arg) : param.value.to_s },
        '?' => ->(param) { param.unset_or_null? ? param.raise_unset : param.value.to_s },
        '+' => ->(param) { param.unset_or_null? ? '' : param.arg }
      }.freeze
    end
  end
end
