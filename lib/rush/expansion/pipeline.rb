# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. With quoting in place a word
    # expands to one field formed by concatenating its segment values (quotes are
    # already removed by the scanner). Parameter, command and arithmetic
    # expansion plus field splitting and globbing arrive in later slices.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: each word becomes one field (no field splitting yet).
      def expand(words) = words.map { |word| expand_word(word) }

      # Assignment RHS / redirection target: a single concatenated field.
      def expand_value(word) = expand_word(word)

      private

      def expand_word(word) = word.segments.map(&:value).join
    end
  end
end
