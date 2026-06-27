# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Slice 1 performs literal
    # expansion (one field per word, no splitting). Tilde, parameter, command and
    # arithmetic expansion, field splitting, globbing and quote removal arrive in
    # later slices, each a collaborator behind these two entry points.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: each word becomes one field (no field splitting yet).
      def expand(words) = words.map(&:literal_text)

      # Assignment RHS / redirection target: a single word, no field splitting.
      def expand_value(word) = word.literal_text
    end
  end
end
