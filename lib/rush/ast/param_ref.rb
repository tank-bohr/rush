# frozen_string_literal: true

module Rush
  module AST
    # Parses the body of ${...}: a parameter name, an optional operator (- = ? +,
    # possibly prefixed with ':'), and the raw operator word.
    PARAM_BRACED = /\A(\w+|[@*#?$!0-])(:?[-=?+])?(.*)\z/m

    # A parameter reference parsed from $name or ${...}. The operator word is
    # expanded lazily at expansion time. Length/strip forms arrive in Phase 2.
    ParamRef = Data.define(:name, :op, :arg) do
      def self.simple(name) = new(name: name, op: nil, arg: nil)

      def self.parse(body)
        match = PARAM_BRACED.match(body)
        new(name: match[1], op: match[2], arg: match[3])
      end
    end
  end
end
