# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. A word expands to one field
    # formed by concatenating its expanded segments: literal segments contribute
    # their (quote-removed) value, :param segments are parameter-expanded. Field
    # splitting, command substitution and globbing arrive in later slices.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: each word becomes one field (no field splitting yet).
      def expand(words) = words.map { |word| expand_word(word) }

      # Assignment RHS / redirection target / operator word: a single field.
      def expand_value(word) = expand_word(word)

      private

      def expand_word(word) = word.segments.map { |segment| expand_segment(segment) }.join

      def expand_segment(segment)
        return segment.value if segment.kind == :literal

        ParameterExpander.new(@executor, segment.value).expand
      end
    end
  end
end
