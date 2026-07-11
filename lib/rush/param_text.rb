# typed: true
# frozen_string_literal: true

module Rush
  # A runtime string subjected to parameter expansion ONLY — the treatment
  # POSIX gives PS1/PS2 prompts and the ENV pathname: $name and ${...} become
  # ParamSegments via the shared ParamScanner; any other character — including
  # command substitution, backticks and backslashes — is literal text. #word
  # yields the segments for Expansion::Pipeline#expand_value.
  class ParamText
    extend T::Sig

    sig { params(text: String).void }
    def initialize(text)
      @scanner = StringScanner.new(text)
      @buffer = SegmentBuffer.new
    end

    sig { returns(AST::Word) }
    def word
      step until @scanner.eos?
      @buffer.word
    end

    private

    sig { void }
    def step
      char = T.must(@scanner.getch)
      char == '$' ? dollar : @buffer << char
    end

    sig { void }
    def dollar
      ref = Lexer::ParamScanner.new(@scanner, quoted: false).read
      ref ? @buffer.push(AST::ParamSegment.new(ref, false)) : @buffer << '$'
    end
  end
end
