# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Expands one ParamRef to a string: resolves the base value, then applies the
    # operator form (if any). The operator word is itself expanded (so
    # ${x:-$y} works) by re-scanning it into a Word and running it back through
    # the expansion pipeline.
    class ParameterExpander
      extend T::Sig

      # Operators handled here rather than by the FORMS lambdas: the ${#p} length
      # and the # ## % %% pattern-removal forms.
      SPECIAL = { '#len' => :length, '#' => :strip, '##' => :strip, '%' => :strip, '%%' => :strip }.freeze

      sig { params(executor: Executor, ref: AST::ParamRef).void }
      def initialize(executor, ref)
        @executor = executor
        @ref = ref
      end

      sig { returns(String) }
      def expand
        op = @ref.op
        return plain unless op
        return send(SPECIAL.fetch(op)) if SPECIAL.key?(op)

        Parameter::FORMS.fetch(op[-1]).call(self)
      end

      # A bare $x / ${x}: under `set -u` an unset ordinary name or positional is
      # an error (special parameters like $@ are exempt).
      sig { returns(String) }
      def plain
        raise(ExpansionError, "#{@ref.name}: parameter not set") if !value && unbound?

        value.to_s
      end

      sig { returns(T.nilable(String)) }
      def value
        Resolver.new(@executor).resolve(@ref.name)
      end

      sig { returns(T::Boolean) }
      def unset_or_null?
        colon? ? value.nil? || value.to_s.empty? : value.nil?
      end

      sig { returns(String) }
      def arg
        @executor.expander.expand_value(sub_word(@ref.arg))
      end

      sig { params(text: String).returns(String) }
      def assign(text)
        @executor.state.environment.assign(@ref.name, text)
        text
      end

      sig { returns(T.noreturn) }
      def raise_unset
        raise(ExpansionError, "#{@ref.name}: #{message}")
      end

      private

      sig { returns(String) }
      def length
        value.to_s.length.to_s
      end

      sig { returns(String) }
      def strip
        PatternRemoval.new(@executor.system, @ref.op, value.to_s, arg).call
      end

      sig { returns(T::Boolean) }
      def unbound?
        @executor.state.options.on?(:nounset) && @ref.name.match?(/\A([a-zA-Z_]\w*|[1-9]\d*)\z/)
      end

      sig { returns(T::Boolean) }
      def colon?
        @ref.op.start_with?(':')
      end

      sig { returns(String) }
      def message
        @ref.arg.empty? ? 'parameter null or not set' : arg
      end

      sig { params(text: T.untyped).returns(T.untyped) }
      def sub_word(text)
        Lexer::WordScanner.entire(text)
      end
    end
  end
end
