# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Builds scalar and operator-word parts without discarding quote provenance.
    class ParameterParts
      extend T::Sig

      sig { params(executor: Executor, quoted: T::Boolean).void }
      def initialize(executor, quoted)
        @executor = executor
        @quoted = quoted
      end

      sig { params(text: String).returns(T::Array[FieldPart]) }
      def scalar(text)
        [[text, !@quoted, false, @quoted]]
      end

      sig { params(text: String).returns(T::Array[FieldPart]) }
      def operator(text)
        operator_word = word(text)
        expanded = @executor.expander.expand_parts(operator_word, tilde: tilde_mode)
        normalized(preserve_empty_at(expanded, operator_word))
      end

      sig { params(parts: T::Array[FieldPart]).returns(String) }
      def collapse(parts)
        @executor.expander.collapse(parts)
      end

      sig { params(text: String).returns(String) }
      def pattern(text)
        @executor.expander.expand_pattern(word(text), tilde: tilde_mode)
      end

      private

      sig { params(expanded: T::Array[FieldPart], operator_word: AST::Word).returns(T::Array[FieldPart]) }
      def preserve_empty_at(expanded, operator_word)
        return expanded unless expanded.empty? && operator_word.segments.any?(&:quoted)

        [['', false, false, true]]
      end

      sig { params(expanded: T::Array[FieldPart]).returns(T::Array[FieldPart]) }
      def normalized(expanded)
        expanded.map do |value, _splittable, brk, quoted|
          protected = @quoted || quoted
          [value, !protected, brk, protected]
        end
      end

      sig { params(text: String).returns(AST::Word) }
      def word(text)
        @quoted ? Lexer::QuotedWord.new(text).word : Lexer::WordScanner.entire(text)
      end

      sig { returns(Symbol) }
      def tilde_mode
        @quoted ? :none : :leading
      end
    end

    # Expands one ParamRef to quote-aware field parts: resolves the base value,
    # then applies the operator form (if any). The operator word is itself expanded (so
    # ${x:-$y} works) by re-scanning it into a Word and running it back through
    # the expansion pipeline. `quoted` picks the word's re-scan rules: a ${...}
    # inside double quotes or a here-doc keeps single quotes ordinary and
    # skips tilde expansion, as dash does.
    class ParameterExpander
      extend T::Sig

      # Operators handled here rather than by the FORMS lambdas: the ${#p} length
      # and the # ## % %% pattern-removal forms.
      PATTERN_REMOVAL = ['#', '##', '%', '%%'].freeze

      sig { params(executor: Executor, ref: AST::ParamRef, quoted: T::Boolean).void }
      def initialize(executor, ref, quoted:)
        @executor = executor
        @ref = ref
        @quoted = quoted
        @parts = ParameterParts.new(executor, quoted)
      end

      sig { returns(String) }
      def expand
        @parts.collapse(expand_parts)
      end

      sig { returns(T::Array[FieldPart]) }
      def expand_parts
        op = @ref.op
        return @parts.scalar(plain) unless op
        return @parts.scalar(length) if op == '#len'
        return @parts.scalar(strip(op)) if PATTERN_REMOVAL.include?(op)

        Parameter::FORMS.fetch(op.delete_prefix(':')).call(self)
      end

      # A bare $x / ${x}: under `set -u` an unset ordinary name or positional is
      # an error (special parameters like $@ are exempt).
      sig { returns(String) }
      def plain
        current = value
        raise(ExpansionError, "#{@ref.name}: parameter not set") if !current && unbound?

        current || ''
      end

      sig { returns(T.nilable(String)) }
      def value
        Resolver.new(@executor).resolve(@ref.name)
      end

      sig { returns(String) }
      def value_text
        value || ''
      end

      sig { returns(T::Boolean) }
      def unset_or_null?
        case value
        in nil then true
        in '' then colon?
        else false
        end
      end

      sig { returns(String) }
      def arg
        @parts.collapse(arg_parts)
      end

      sig { returns(T::Array[FieldPart]) }
      def arg_parts
        @parts.operator(argument)
      end

      sig { returns(T::Array[FieldPart]) }
      def value_parts
        @parts.scalar(value_text)
      end

      sig { returns(T::Array[FieldPart]) }
      def empty_parts
        @parts.scalar('')
      end

      sig { returns(T::Array[FieldPart]) }
      def assign_parts
        text = @parts.collapse(arg_parts)
        @executor.state.variables.assign(@ref.name, text)
        @parts.scalar(text)
      end

      sig { returns(T.noreturn) }
      def raise_unset
        raise(ExpansionError, "#{@ref.name}: #{message}")
      end

      private

      sig { returns(String) }
      def length
        value_text.length.to_s
      end

      sig { params(op: String).returns(String) }
      def strip(op)
        PatternRemoval.new(@executor.system, op, value_text, pattern_arg).call
      end

      sig { returns(String) }
      def pattern_arg
        @parts.pattern(argument)
      end

      sig { returns(T::Boolean) }
      def unbound?
        @executor.state.options.on?(:nounset) && @ref.name.match?(/\A([a-zA-Z_]\w*|[1-9]\d*)\z/)
      end

      sig { returns(T::Boolean) }
      def colon?
        op = @ref.op
        !!(op && op.start_with?(':'))
      end

      sig { returns(String) }
      def message
        argument.empty? ? 'parameter null or not set' : arg
      end

      sig { returns(String) }
      def argument
        @ref.arg || ''
      end
    end
  end
end
