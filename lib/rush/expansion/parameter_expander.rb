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
        return plain unless @ref.op
        return send(SPECIAL.fetch(@ref.op)) if SPECIAL.key?(@ref.op)

        Parameter::FORMS.fetch(@ref.op[-1]).call(self)
      end

      # A bare $x / ${x}: under `set -u` an unset ordinary name or positional is
      # an error (special parameters like $@ are exempt).
      def plain
        raise(ExpansionError, "#{@ref.name}: parameter not set") if value.nil? && unbound?

        value.to_s
      end

      def value = Resolver.new(@executor).resolve(@ref.name)

      def unset_or_null?
        colon? ? value.nil? || value.empty? : value.nil?
      end

      def arg = @executor.expander.expand_value(sub_word(@ref.arg))

      def assign(text)
        @executor.state.environment.assign(@ref.name, text)
        text
      end

      def raise_unset = raise(ExpansionError, "#{@ref.name}: #{message}")

      private

      def length = value.to_s.length.to_s

      def strip = PatternRemoval.new(@executor.system, @ref.op, value.to_s, arg).call

      def unbound? = @executor.state.option?(:nounset) && @ref.name.match?(/\A([a-zA-Z_]\w*|[1-9]\d*)\z/)

      def colon? = @ref.op.start_with?(':')

      def message = @ref.arg.empty? ? 'parameter null or not set' : arg

      def sub_word(text) = Lexer::WordScanner.new(StringScanner.new(text), whole: true).scan
    end
  end
end
