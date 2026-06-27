# frozen_string_literal: true

module Rush
  module Expansion
    # Entry point for IFS field splitting: it classifies IFS into its whitespace
    # and non-whitespace delimiter sets and hands the parts to IfsScanner, which
    # applies the three POSIX cases. Unset IFS means the default whitespace set
    # (<space><tab><newline>); a null IFS (the empty string) leaves both sets
    # empty, so no character delimits and only quoting/breaks form fields.
    class FieldSplitter
      WHITESPACE = " \t\n"

      def initialize(ifs)
        @chars = (ifs || WHITESPACE).chars.uniq
      end

      def split(parts) = IfsScanner.new(whitespace, others).run(parts)

      private

      def whitespace = @chars.select { |char| WHITESPACE.include?(char) }

      def others = @chars.reject { |char| WHITESPACE.include?(char) }
    end
  end
end
