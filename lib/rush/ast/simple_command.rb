# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=val ... cmd arg ... >file` — variable assignments, argv words and
    # redirections (in source order within each group).
    class SimpleCommand < Node
      extend T::Sig

      attr_reader :assignments, :words, :redirects, :source_line

      sig { params(parts: T::Array[T.untyped]).returns(SimpleCommand) }
      def self.from_parts(parts)
        new(parts.grep(Assignment), parts.grep(Word), parts.grep(Redirect), source_line: source_line(parts))
      end

      sig { params(parts: T::Array[T.untyped]).returns(Integer) }
      def self.source_line(parts)
        parts.map(&:source_line).min || 1
      end

      sig do
        params(assignments: T::Array[Assignment], words: T::Array[Word], redirects: T::Array[Redirect],
               source_line: Integer).void
      end
      def initialize(assignments, words, redirects, source_line: 1)
        @assignments = assignments
        @words = words
        @redirects = redirects
        @source_line = source_line
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        executor.state.record_lineno(source_line)
        executor.run_simple(self)
      end
    end
  end
end
