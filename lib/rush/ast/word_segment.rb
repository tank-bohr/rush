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
      attr_reader :value, :quoted

      def initialize(value, quoted)
        @value = value
        @quoted = quoted
      end

      def literal_value
        nil
      end

      def splittable?
        false
      end

      def splat?
        false
      end

      # A copy with a rewritten value (e.g. after tilde expansion).
      def with_value(new_value)
        self.class.new(new_value, quoted)
      end

      def ==(other)
        other.instance_of?(self.class) && value == other.value && quoted == other.quoted
      end

      alias eql? ==

      def hash
        [self.class, value, quoted].hash
      end
    end

    # Literal text. It expands to itself, can act as a bare name when unquoted,
    # and is never field-split.
    class LiteralSegment < WordSegment
      def expand(_executor)
        value
      end

      def literal_value
        (value unless quoted)
      end
    end

    # A segment substituted at expansion time (param / command / arithmetic): its
    # unquoted result undergoes field splitting.
    class DynamicSegment < WordSegment
      def splittable?
        !quoted
      end
    end

    # $name / ${...}: value is the ParamRef.
    class ParamSegment < DynamicSegment
      def expand(executor)
        Expansion::ParameterExpander.new(executor, value).expand
      end

      # $@ (always) and unquoted $* expand to one field per positional parameter.
      def splat?
        !value.op && (value.name == '@' || (value.name == '*' && !quoted))
      end
    end

    # $(...) / `...`: value is the command-substitution source.
    class CommandSegment < DynamicSegment
      def expand(executor)
        Expansion::CommandSubstitution.new(executor, value).expand
      end
    end

    # $((...)): value is the arithmetic source.
    class ArithSegment < DynamicSegment
      def expand(executor)
        Expansion::ArithmeticExpander.new(executor, value).expand
      end
    end
  end
end
