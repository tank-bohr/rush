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
      @segments = T.let([], T::Array[AST::WordSegment[T.untyped]])
      @literal = +''
    end

    sig { returns(AST::Word) }
    def word
      step until @scanner.eos?
      flush
      AST::Word.new(@segments)
    end

    private

    sig { void }
    def step
      char = T.must(@scanner.getch)
      char == '$' ? dollar : @literal << char
    end

    sig { void }
    def dollar
      ref = Lexer::ParamScanner.new(@scanner).read
      ref ? push(AST::ParamSegment.new(ref, false)) : @literal << '$'
    end

    sig { params(segment: AST::WordSegment[T.untyped]).void }
    def push(segment)
      flush
      @segments << segment
    end

    sig { void }
    def flush
      return if @literal.empty?

      @segments << AST::LiteralSegment.new(@literal, false)
      @literal = +''
    end
  end
end
