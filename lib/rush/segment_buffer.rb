# typed: true
# frozen_string_literal: true

module Rush
  # Accumulates a word's segments during scanning: literal characters gather
  # into a pending run, #push closes that run as an unquoted LiteralSegment
  # before appending a structured segment, and #word closes it once more to
  # build the finished AST::Word. Shared by the scanners that assemble words
  # character by character (WordScanner, HeredocBody, ParamText).
  class SegmentBuffer
    extend T::Sig

    sig { void }
    def initialize
      @segments = T.let([], T::Array[AST::AnySegment])
      @literal = +''
    end

    sig { params(text: String).returns(T.self_type) }
    def <<(text)
      @literal << text
      self
    end

    sig { params(segment: AST::AnySegment).void }
    def push(segment)
      flush
      @segments << segment
    end

    sig { returns(AST::Word) }
    def word
      flush
      AST::Word.new(@segments)
    end

    private

    sig { void }
    def flush
      return if @literal.empty?

      @segments << AST::LiteralSegment.new(@literal, false)
      @literal = +''
    end
  end
end
