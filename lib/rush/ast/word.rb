# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # An unexpanded word: an ordered list of typed segments. The expander turns
    # the segments into fields; `literal_text` is the simple concatenation used
    # for error messages and (unquoted) assignment-name detection.
    class Word < Node
      extend T::Sig

      attr_reader :segments, :source_line

      sig { params(segments: T::Array[WordSegment[T.untyped]], source_line: Integer).void }
      def initialize(segments, source_line: 1)
        @segments = segments
        @source_line = source_line
      end

      sig { params(text: String, source_line: Integer).returns(Word) }
      def self.literal(text, source_line: 1)
        new([LiteralSegment.new(text, false)], source_line: source_line)
      end

      sig { returns(String) }
      def literal_text
        segments.map(&:value).join
      end

      # The text when this word is a bare name — one unquoted literal segment, no
      # quoting or substitution — else nil. Used for reserved words, NAME=, and
      # alias substitution, all of which only apply to a plain literal word.
      sig { returns(T.nilable(String)) }
      def literal_name
        (segments.first.literal_value if segments.one?)
      end

      sig { returns(T.nilable(String)) }
      def first_literal_value
        segments.fetch(0).literal_value
      end
    end
  end
end
