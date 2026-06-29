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
      # Operators handled here rather than by the FORMS lambdas: the ${#p} length
      # and the # ## % %% pattern-removal forms.
      SPECIAL = { '#len' => :length, '#' => :strip, '##' => :strip, '%' => :strip, '%%' => :strip }.freeze

      def initialize(executor, ref)
        @executor = executor
        @ref = ref
      end

      def expand
        op = @ref.op
        return plain unless op
        return send(SPECIAL.fetch(op)) if SPECIAL.key?(op)

        Parameter::FORMS.fetch(op[-1]).call(self)
      end

      # A bare $x / ${x}: under `set -u` an unset ordinary name or positional is
      # an error (special parameters like $@ are exempt).
      def plain
        raise(ExpansionError, "#{@ref.name}: parameter not set") if !value && unbound?

        value.to_s
      end

      def value
        Resolver.new(@executor).resolve(@ref.name)
      end

      def unset_or_null?
        colon? ? value.nil? || value.to_s.empty? : value.nil?
      end

      def arg
        @executor.expander.expand_value(sub_word(@ref.arg))
      end

      def assign(text)
        @executor.state.environment.assign(@ref.name, text)
        text
      end

      def raise_unset
        raise(ExpansionError, "#{@ref.name}: #{message}")
      end

      private

      def length
        value.to_s.length.to_s
      end

      def strip
        PatternRemoval.new(@executor.system, @ref.op, value.to_s, arg).call
      end

      def unbound?
        @executor.state.options.on?(:nounset) && @ref.name.match?(/\A([a-zA-Z_]\w*|[1-9]\d*)\z/)
      end

      def colon?
        @ref.op.start_with?(':')
      end

      def message
        @ref.arg.empty? ? 'parameter null or not set' : arg
      end

      def sub_word(text)
        Lexer::WordScanner.entire(text)
      end
    end
  end
end
