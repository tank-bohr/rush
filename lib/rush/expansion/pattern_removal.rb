# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Implements ${p#pat} ${p##pat} ${p%pat} ${p%%pat}: remove from the value the
    # smallest (#/%) or largest (##/%%) prefix (#) or suffix (%) that matches the
    # glob pattern, leaving the value unchanged when nothing matches.
    class PatternRemoval
      def initialize(system, op, value, pattern)
        @system = system
        @op = op
        @value = value
        @pattern = pattern
      end

      def call
        @op.start_with?('#') ? strip_prefix : strip_suffix
      end

      private

      def strip_prefix
        hit = order(prefixes).find { |part| match?(part) }
        hit ? @value[hit.length..].to_s : @value
      end

      def strip_suffix
        hit = order(suffixes).find { |part| match?(part) }
        hit ? @value[0, @value.length - hit.length].to_s : @value
      end

      # The substring indices are all within @value, so the slices are non-nil;
      # .to_s satisfies the Array[String] returns for the checker.
      def prefixes
        (0..@value.length).map { |index| @value[0, index].to_s }
      end

      def suffixes
        (0..@value.length).map { |index| @value[@value.length - index, index].to_s }
      end

      def order(list)
        @op.length == 2 ? list.reverse : list
      end

      def match?(part)
        @system.fnmatch(@pattern, part)
      end
    end
  end
end
