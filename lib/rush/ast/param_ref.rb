# frozen_string_literal: true

module Rush
  module AST
    # Parses the body of ${...}: a parameter name plus an optional operator — the
    # default/assign/error/alternative forms (- = ? +, optionally ':'-prefixed),
    # the prefix/suffix removal forms (# ## % %%), or the ${#name} length form
    # (recognised before the others, since a leading # also names $#).
    PARAM_BRACED = /\A(\w+|[@*#?$!0-])(:?[-=?+]|\#{1,2}|%{1,2})?(.*)\z/m

    # A parameter reference parsed from $name or ${...}. The operator word is
    # expanded lazily at expansion time.
    ParamRef = Data.define(:name, :op, :arg) do
      def self.simple(name) = new(name: name, op: nil, arg: nil)

      def self.parse(body)
        return new(name: body[1..], op: '#len', arg: nil) if length?(body)

        match = PARAM_BRACED.match(body)
        new(name: match[1], op: match[2], arg: match[3])
      end

      def self.length?(body) = body.start_with?('#') && body.length > 1
    end
  end
end
