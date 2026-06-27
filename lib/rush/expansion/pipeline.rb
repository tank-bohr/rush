# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Phase 0 performs literal
    # expansion only (one field per word). Tilde, parameter, command and
    # arithmetic expansion, field splitting, globbing and quote removal land in
    # later phases, each as its own collaborator behind this single entry point.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      def expand(words) = words.map(&:literal_text)
    end
  end
end
