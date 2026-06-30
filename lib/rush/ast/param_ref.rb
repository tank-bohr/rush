# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # Parses the body of ${...}: a parameter name plus an optional operator — the
    # default/assign/error/alternative forms (- = ? +, optionally ':'-prefixed),
    # the prefix/suffix removal forms (# ## % %%), or the ${#name} length form
    # (recognised before the others, since a leading # also names $#).
    PARAM_BRACED = /\A(\w+|[@*#?$!0-])(:?[-=?+]|\#{1,2}|%{1,2})?(.*)\z/m

    ParamRef = Data.define(:name, :op, :arg)

    # A parameter reference parsed from $name or ${...}. The operator word is
    # expanded lazily at expansion time.
    class ParamRef
      extend T::Sig

      sig { params(name: T.untyped).returns(ParamRef) }
      def self.simple(name)
        new(name: name, op: nil, arg: nil)
      end

      sig { params(body: T.untyped).returns(ParamRef) }
      def self.parse(body)
        return new(name: body[1..], op: '#len', arg: nil) if length?(body)

        # PARAM_BRACED's \A…\z with a trailing .* always matches; .to_a pins the
        # MatchData? to an Array so the captures are reachable without a nil branch.
        captures = PARAM_BRACED.match(body).to_a
        new(name: captures[1], op: captures[2], arg: captures[3])
      end

      sig { params(body: T.untyped).returns(T::Boolean) }
      def self.length?(body)
        body.start_with?('#') && body.length > 1
      end
    end
  end
end
