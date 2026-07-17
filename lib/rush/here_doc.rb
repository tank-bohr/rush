# typed: true
# frozen_string_literal: true

module Rush
  # A here-document redirect target. The lexer creates it when it sees `<<word`
  # (recording the delimiter, whether it was quoted, and the `<<-` tab strip),
  # then fills #body — an AST::Word — once it collects the body lines at the next
  # newline. It quacks like a Word (responds to #segments) so the expansion
  # pipeline expands the body as a single field at execution time.
  class HereDoc
    extend T::Sig

    # Immutable metadata captured from the delimiter token.
    Definition = Data.define(:delimiter, :quoted, :strip, :source_line)

    sig { returns(AST::Word) }
    attr_reader :body

    sig { params(delimiter: String, quoted: T::Boolean, strip: T::Boolean, source_line: Integer).void }
    def initialize(delimiter:, quoted:, strip:, source_line: 1)
      @definition = T.let(Definition.new(delimiter, quoted, strip, source_line), Definition)
      @body = T.let(AST::Word.new([], source_line: source_line), AST::Word)
    end

    sig { returns(String) }
    def delimiter
      @definition.delimiter
    end

    sig { returns(T::Boolean) }
    def quoted
      @definition.quoted
    end

    sig { returns(T::Boolean) }
    def strip
      @definition.strip
    end

    sig { returns(Integer) }
    def source_line
      @definition.source_line
    end

    # The lexer fills the body — an AST::Word — once it has gathered the body
    # lines at the next newline; it is the only writer, so #body stays read-only.
    sig { params(body: AST::Word).void }
    def fill(body)
      @body = body
    end

    sig { returns(T::Array[AST::WordSegment[T.untyped]]) }
    def segments
      @body.segments
    end
  end
end
