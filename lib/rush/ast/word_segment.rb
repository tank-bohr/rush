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

      attr_reader :value, :quoted

      sig { params(value: T.untyped, quoted: T::Boolean).void }
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

      sig { returns(T.untyped) }
      def literal_value
        nil
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
      sig { params(new_value: T.untyped).returns(WordSegment) }
      def with_value(new_value)
        self.class.new(new_value, quoted)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        other.instance_of?(self.class) && value == other.value && quoted == other.quoted
      end

      alias eql? ==

      sig { returns(Integer) }
      def hash
        [self.class, value, quoted].hash
      end
    end

    # Literal text. It expands to itself, can act as a bare name when unquoted,
    # and is never field-split.
    class LiteralSegment < WordSegment
      extend T::Sig

      sig { params(_executor: Executor).returns(String) }
      def expand(_executor)
        value
      end

      sig { returns(T.untyped) }
      def literal_value
        (value unless quoted)
      end
    end

    # A segment substituted at expansion time (param / command / arithmetic): its
    # unquoted result undergoes field splitting.
    class DynamicSegment < WordSegment
      extend T::Sig

      sig { returns(T::Boolean) }
      def splittable?
        !quoted
      end
    end

    # $name / ${...}: value is the ParamRef.
    class ParamSegment < DynamicSegment
      extend T::Sig

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::ParameterExpander.new(executor, value).expand
      end

      # $@ (always) and unquoted $* expand to one field per positional parameter.
      sig { returns(T::Boolean) }
      def splat?
        !value.op && (value.name == '@' || (value.name == '*' && !quoted))
      end
    end

    # $(...) / `...`: value is the command-substitution source.
    class CommandSegment < DynamicSegment
      extend T::Sig

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::CommandSubstitution.new(executor, value).expand
      end
    end

    # $((...)): value is the arithmetic source.
    class ArithSegment < DynamicSegment
      extend T::Sig

      sig { params(executor: Executor).returns(String) }
      def expand(executor)
        Expansion::ArithmeticExpander.new(executor, value).expand
      end
    end
  end
end
