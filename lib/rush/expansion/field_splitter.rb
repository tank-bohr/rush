# frozen_string_literal: true

module Rush
  module Expansion
    # Entry point for IFS field splitting: it hands the parts and the IFS
    # delimiter sets (an Ifs value) to IfsScanner, which applies the three POSIX
    # cases.
    class FieldSplitter
      def initialize(ifs)
        @ifs = Ifs.new(ifs)
      end

      def split(parts) = IfsScanner.new(@ifs.whitespace, @ifs.others).run(parts)
    end
  end
end
