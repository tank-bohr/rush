# frozen_string_literal: true

module Rush
  module AST
    # An unexpanded word: an ordered list of typed segments. The expander turns
    # the segments into fields; `literal_text` is the simple concatenation used
    # for error messages and (unquoted) assignment-name detection.
    class Word < Node
      attr_reader :segments

      def initialize(segments)
        super()
        @segments = segments
      end

      def self.literal(text) = new([WordSegment.new(kind: :literal, value: text, quoted: false)])

      def literal_text = segments.map(&:value).join

      # A bare unquoted-literal word — one literal segment, no quoting or
      # substitution — so its text can stand in as a name (e.g. for an alias).
      def plain? = segments.one? && segments.first.literal_unquoted?
    end
  end
end
