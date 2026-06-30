# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # One element of a list: an and-or list and whether it was terminated by `&`.
    ListEntry = Data.define(:and_or, :async)

    # A `;` / `&` / newline-separated list of and-or lists and the program root.
    # Runs each entry in order; the list's status is the last entry's. An empty
    # list (a blank or comment-only line, which is its own program under
    # command-by-command reading) preserves $?, like dash. Async (`&`) execution
    # lands with the fork slice; for now it is parsed and recorded but run
    # synchronously.
    class List < Node
      extend T::Sig

      attr_reader :entries

      sig { params(entries: T::Array[ListEntry]).void }
      def initialize(entries)
        super()
        @entries = entries
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        entries.reduce(executor.state.last_status) { |_status, entry| run_entry(executor, entry) }
      end

      # A blank or comment-only program runs no command; SourceRunner skips it
      # when tracking eval/dot's result status.
      sig { returns(T::Boolean) }
      def empty?
        entries.empty?
      end

      private

      # An async (&) command is exempt from errexit, so it runs in a tested context.
      sig { params(executor: Executor, entry: ListEntry).returns(Status) }
      def run_entry(executor, entry)
        return executor.tested { executor.run(entry.and_or) } if entry.async

        executor.run(entry.and_or)
      end
    end
  end
end
