# frozen_string_literal: true

module Rush
  module AST
    # An unexpanded word: an ordered list of typed segments. Phase 0 holds a
    # single :literal segment and expands to its concatenated text verbatim.
    class Word < Node
      attr_reader :segments

      def initialize(segments)
        super()
        @segments = segments
      end

      def self.literal(text) = new([WordSegment.new(kind: :literal, text: text)])

      def literal_text = segments.map(&:text).join
    end
  end
end
