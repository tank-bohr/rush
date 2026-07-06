# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=val ... cmd arg ... >file` — variable assignments, argv words and
    # redirections, preserving both grouped accessors and original source parts.
    class SimpleCommand < Node
      extend T::Sig

      Part = T.type_alias { T.any(Assignment, Word, Redirect) }

      attr_reader :parts, :source_line

      sig { params(parts: T::Array[T.untyped]).returns(SimpleCommand) }
      def self.from_parts(parts)
        new(parts.grep(Assignment), parts.grep(Word), parts.grep(Redirect), source_line: source_line(parts))
          .tap { |command| command.parts.replace(parts) }
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
        @parts = T.let(assignments + words + redirects, T::Array[Part])
        @source_line = source_line
      end

      sig { returns(T::Array[Assignment]) }
      def assignments
        result = T.let([], T::Array[Assignment])
        parts.each { |part| result << part if part.is_a?(Assignment) }
        result
      end

      sig { returns(T::Array[Word]) }
      def words
        result = T.let([], T::Array[Word])
        parts.each { |part| result << part if part.is_a?(Word) }
        result
      end

      sig { returns(T::Array[Redirect]) }
      def redirects
        result = T.let([], T::Array[Redirect])
        parts.each { |part| result << part if part.is_a?(Redirect) }
        result
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        executor.state.record_lineno(source_line)
        executor.run_simple(self)
      end
    end
  end
end
