# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # A typed piece of a word. Subclasses know how to expand themselves (the
    # segment-level counterpart of a command node's #execute), so there is no
    # `kind` to dispatch on: `quoted` records whether it came from a quoted
    # context (which governs field splitting and pathname expansion), `value` is
    # the kind-specific payload (literal text, a ParamRef, or substitution
    # source). literal_value is the text when the segment can stand in as a bare
    # name; splittable?/splat? are its field-splitting roles.
    class WordSegment
      extend T::Sig
      extend T::Generic

      Value = type_member

      sig { returns(Value) }
      attr_reader :value

      sig { returns(T::Boolean) }
      attr_reader :quoted

      sig { params(value: Value, quoted: T::Boolean).void }
      def initialize(value, quoted)
        @value = value
        @quoted = quoted
      end

      # Each concrete segment expands itself to a string (the segment-level
      # counterpart of a command node's #execute); the base is abstract.
      sig { params(_executor: Executor).returns(String) }
      def expand(_executor)
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      # mutant:disable -- `nil` is the default "not a literal" value; an empty
      # method body has the same public semantics for this abstract fallback.
      def literal_value
        nil
      end

      # This segment as dash's canonical job text prints it (CommandText):
      # each kind re-spells itself; the base is abstract.
      sig { returns(String) }
      def canon
        raise NotImplementedError
      end

      sig { returns(T::Boolean) }
      def splittable?
        false
      end

      sig { returns(T::Boolean) }
      def splat?
        false
      end

      # A copy with a rewritten value (e.g. after tilde expansion).
      sig { params(new_value: Value).returns(WordSegment[Value]) }
      def with_value(new_value)
        self.class.new(new_value, quoted)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.instance_of?(self.class)
        return false unless equality_value.eql?(other.equality_value)
        return false unless quoted.eql?(other.quoted)

        true
      end

      alias eql? ==

      sig { returns(T.untyped) }
      def equality_value
        value
      end

      sig { returns(Integer) }
      def hash
        [self.class, value, quoted].hash
      end
    end

    # Literal text. It expands to itself, can act as a bare name when unquoted,
    # and is never field-split.
    class LiteralSegment < WordSegment
      extend T::Sig
      extend T::Generic

      Value = type_member { { fixed: String } }

      # dash escapes \ " $ ` inside the double quotes a quoted run gets.
      CANON_ESCAPES = T.let(/[\\"$`]/, Regexp)

      sig { params(_executor: Executor).returns(String) }
      def expand(_executor)
        value
      end

      sig { returns(T.nilable(String)) }
      def literal_value
        (value unless quoted)
      end

      sig { returns(String) }
      def canon
        quoted ? value.gsub(CANON_ESCAPES) { |char| "\\#{char}" } : value
      end
    end

    # A segment substituted at expansion time (param / command / arithmetic): its
    # unquoted result undergoes field splitting.
    class DynamicSegment < WordSegment
      extend T::Sig
      extend T::Generic

      Value = type_member

      sig { returns(T::Boolean) }
      def splittable?
        !quoted
      end
    end

    # $name / ${...}: value is the ParamRef.
    class ParamSegment < DynamicSegment
      extend T::Sig
      extend T::Generic

      Value = type_member { { fixed: ParamRef } }

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::ParameterExpander.new(executor, value, quoted: quoted).expand
      end

      # $@ (always) and unquoted $* expand to one field per positional parameter.
      sig { returns(T::Boolean) }
      def splat?
        !value.op && (value.name == '@' || (value.name == '*' && !quoted))
      end

      sig { returns(String) }
      def canon
        value.canon
      end
    end

    # $(...) / `...`: value is the command-substitution source.
    class CommandSegment < DynamicSegment
      extend T::Sig
      extend T::Generic

      Value = type_member { { fixed: String } }

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::CommandSubstitution.new(executor, value).expand
      end

      # dash elides a command substitution's body from the job text.
      sig { returns(String) }
      def canon
        '$(...)'
      end
    end

    # $((...)): value is the arithmetic source.
    class ArithSegment < DynamicSegment
      extend T::Sig
      extend T::Generic

      Value = type_member { { fixed: String } }

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::ArithmeticExpander.new(executor, value).expand
      end

      # An arithmetic expansion keeps its raw source in the job text.
      sig { returns(String) }
      def canon
        "$((#{value}))"
      end
    end
  end
end
