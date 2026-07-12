# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # The IFS value, parsed once into its whitespace and non-whitespace delimiter
    # sets for POSIX field splitting. Unset IFS (nil) defaults to the standard
    # <space><tab><newline>; a null IFS (the empty string) leaves both sets empty,
    # so no character delimits.
    class Ifs
      extend T::Sig

      WHITESPACE = " \t\n"
      DEFAULT_CHARS = WHITESPACE.chars.freeze
      NO_CHARS = T.let(
        [], #: Array[String]
        T::Array[String]
      ).freeze

      sig { params(ifs: T.nilable(String)).void }
      def initialize(ifs)
        @ifs = ifs
        @chars = ifs ? ifs.chars.uniq.freeze : DEFAULT_CHARS
        @whitespace, @others = delimiter_sets
      end

      sig { returns(T::Boolean) }
      def null?
        @ifs == ''
      end

      sig { returns(T::Array[String]) }
      attr_reader :whitespace, :others

      sig { returns(T::Boolean) }
      def preserve_empty_splat?
        @chars.first == @others.first
      end

      sig { params(char: String).returns(T::Boolean) }
      def whitespace?(char)
        !!(@chars.include?(char) && WHITESPACE.include?(char))
      end

      sig { params(char: String).returns(T::Boolean) }
      def other?(char)
        !!(@chars.include?(char) && !WHITESPACE.include?(char))
      end

      private

      sig { returns([T::Array[String], T::Array[String]]) }
      def delimiter_sets
        return [DEFAULT_CHARS, NO_CHARS] unless @ifs
        return [NO_CHARS, NO_CHARS] if @chars.empty?

        whitespace, others = @chars.partition { |char| WHITESPACE.include?(char) }
        [whitespace.freeze, others.freeze]
      end
    end
  end
end
