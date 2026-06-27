# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Expands one ParamRef to a string: resolves the base value, then applies the
    # operator form (if any). The operator word is itself expanded (so
    # ${x:-$y} works) by re-scanning it into a Word and running it back through
    # the expansion pipeline.
    class ParameterExpander
      def initialize(executor, ref)
        @executor = executor
        @ref = ref
      end

      def expand
        return value.to_s unless @ref.op

        Parameter::FORMS.fetch(@ref.op[-1]).call(self)
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

      def colon? = @ref.op.start_with?(':')

      def message = @ref.arg.empty? ? 'parameter null or not set' : arg

      def sub_word(text) = Lexer::WordScanner.new(StringScanner.new(text), whole: true).scan
    end
  end
end
