# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Expands one ParamRef to a string: resolves the base value, then applies the
    # operator form (if any). The operator word is itself expanded (so
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
      end

      sig { returns(String) }
      def expand
        op = @ref.op
        return plain unless op
        return length if op == '#len'
        return strip(op) if PATTERN_REMOVAL.include?(op)

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
        @executor.expander.expand_value(sub_word(argument), tilde: tilde_mode)
      end

      sig { params(text: String).returns(String) }
      def assign(text)
        @executor.state.variables.assign(@ref.name, text)
        text
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
        @executor.expander.expand_pattern(sub_word(argument), tilde: tilde_mode)
      end

      sig { returns(Symbol) }
      def tilde_mode
        @quoted ? :none : :leading
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

      sig { params(text: String).returns(AST::Word) }
      def sub_word(text)
        @quoted ? Lexer::QuotedWord.new(text).word : Lexer::WordScanner.entire(text)
      end
    end
  end
end
