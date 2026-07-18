# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=val ... cmd arg ... >file` — variable assignments, argv words and
    # redirections, preserving both grouped accessors and original source parts.
    class SimpleCommand < Node
      extend T::Sig

      Part = T.type_alias { T.any(Assignment, Word, Redirect) }

      sig { returns(T::Array[Part]) }
      attr_reader :parts

      sig { returns(Integer) }
      attr_reader :source_line

      sig do
        params(assignments: T::Array[Assignment], words: T::Array[Word], redirects: T::Array[Redirect],
               source_line: Integer).returns(SimpleCommand)
      end
      def self.from_groups(assignments, words, redirects, source_line: 1)
        new(assignments + words + redirects, source_line: source_line)
      end

      sig { params(parts: T::Array[Part]).returns(Integer) }
      def self.source_line(parts)
        parts.map(&:source_line).min || 1
      end

      sig { params(parts: T::Array[Part], source_line: Integer).void }
      def initialize(parts, source_line: self.class.source_line(parts))
        @parts = parts
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
