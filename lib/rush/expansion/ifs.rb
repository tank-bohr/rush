# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # The IFS value, parsed once into its whitespace and non-whitespace delimiter
    # sets for POSIX field splitting. Unset IFS (nil) defaults to the standard
    # <space><tab><newline>; a null IFS (the empty string) leaves both sets empty,
    # so no character delimits.
    class Ifs
      WHITESPACE = " \t\n"

      def initialize(ifs)
        @ifs = ifs
        @chars = (ifs || WHITESPACE).chars.uniq
      end

      def null?
        @ifs == ''
      end

      def whitespace
        @chars.select { |char| WHITESPACE.include?(char) }
      end

      def others
        @chars.reject { |char| WHITESPACE.include?(char) }
      end
    end
  end
end
