# frozen_string_literal: true

module Rush
  module AST
    # One element of a list: an and-or list and whether it was terminated by `&`.
    ListEntry = Data.define(:and_or, :async)

    # A `;` / `&` / newline-separated list of and-or lists and the program root.
    # Runs each entry in order; the list's status is the last entry's (0 when
    # empty). Async (`&`) execution lands with the fork slice; for now it is
    # parsed and recorded but executed synchronously.
    class List < Node
      attr_reader :entries

      def initialize(entries)
        super()
        @entries = entries
      end

      def execute(executor)
        entries.reduce(Status.success) { |_, entry| run_entry(executor, entry) }
      end

      private

      # An async (&) command is exempt from errexit, so it runs in a tested context.
      def run_entry(executor, entry)
        return executor.tested { executor.run(entry.and_or) } if entry.async

        executor.run(entry.and_or)
      end
    end
  end
end
