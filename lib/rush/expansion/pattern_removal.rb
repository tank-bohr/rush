# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Implements ${p#pat} ${p##pat} ${p%pat} ${p%%pat}: remove from the value the
    # smallest (#/%) or largest (##/%%) prefix (#) or suffix (%) that matches the
    # glob pattern, leaving the value unchanged when nothing matches.
    class PatternRemoval
      extend T::Sig

      sig { params(executor: Executor, op: String, value: String, pattern: String).void }
      def initialize(executor, op, value, pattern)
        @executor = executor
        @op = op
        @value = value
        @pattern = pattern
      end

      sig { returns(String) }
      def call
        @op.start_with?('#') ? strip_prefix : strip_suffix
      end

      private

      sig { returns(String) }
      def strip_prefix
        hit = order(prefixes).find { |part| match?(part) }
        hit ? @value.delete_prefix(hit) : @value
      end

      sig { returns(String) }
      def strip_suffix
        hit = order(suffixes).find { |part| match?(part) }
        hit ? @value.delete_suffix(hit) : @value
      end

      sig { returns(T::Array[String]) }
      def prefixes
        current = +''
        @value.each_char.with_object(['']) { |char, result| result << (current += char) }
      end

      sig { returns(T::Array[String]) }
      def suffixes
        current = +''
        @value.each_char.reverse_each.with_object(['']) { |char, result| result << (current = char + current) }
      end

      sig { params(list: T::Array[String]).returns(T::Array[String]) }
      def order(list)
        @op.length == 2 ? list.reverse : list
      end

      sig { params(part: String).returns(T::Boolean) }
      def match?(part)
        locale = @executor.state.variables.locale_settings
        @executor.system.fnmatch?(@pattern, part, locale: locale)
      end
    end
  end
end
