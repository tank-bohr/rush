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

      sig { params(name: String).returns(ParamRef) }
      def self.simple(name)
        new(name: name, op: nil, arg: nil)
      end

      sig { params(body: String).returns(ParamRef) }
      def self.parse(body)
        return new(name: body.delete_prefix('#'), op: '#len', arg: nil) if length?(body)

        match = braced_match(body)
        new(name: braced_name(match), op: match[2], arg: match[3])
      end

      sig { params(body: String).returns(T::Boolean) }
      def self.length?(body)
        body.start_with?('#') && body.length > 1
      end

      # dash's job text always braces a parameter — ${T}, "${@}", ${T:-9}
      # with the op's raw source argument (CommandText).
      sig { returns(String) }
      def canon
        return "${##{name}}" if op == '#len'

        "${#{name}#{op}#{arg}}"
      end

      sig { params(body: String).returns(MatchData) }
      def self.braced_match(body)
        PARAM_BRACED.match(body) || raise(ExpansionError, 'bad substitution')
      end
      private_class_method :braced_match

      sig { params(match: MatchData).returns(String) }
      def self.braced_name(match)
        match[1] || raise(ExpansionError, 'bad substitution')
      end
      private_class_method :braced_name
    end
  end
end
