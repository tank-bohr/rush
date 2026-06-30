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

      sig { params(ifs: T.nilable(String)).void }
      def initialize(ifs)
        @ifs = ifs
        @chars = (ifs || WHITESPACE).chars.uniq
      end

      sig { returns(T::Boolean) }
      def null?
        @ifs == ''
      end

      sig { returns(T::Array[String]) }
      def whitespace
        @chars.select { |char| WHITESPACE.include?(char) }
      end

      sig { returns(T::Array[String]) }
      def others
        @chars.reject { |char| WHITESPACE.include?(char) }
      end
    end
  end
end
