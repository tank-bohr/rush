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

      def self.literal(text)
        new([LiteralSegment.new(text, false)])
      end

      def literal_text
        segments.map(&:value).join
      end

      # The text when this word is a bare name — one unquoted literal segment, no
      # quoting or substitution — else nil. Used for reserved words, NAME=, and
      # alias substitution, all of which only apply to a plain literal word.
      def literal_name
        (segments.first.literal_value if segments.one?)
      end
    end
  end
end
