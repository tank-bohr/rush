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

    sig { returns(AST::Word) }
    attr_reader :body

    sig { returns(String) }
    attr_reader :delimiter

    sig { returns(T::Boolean) }
    attr_reader :quoted

    sig { returns(T::Boolean) }
    attr_reader :strip

    sig { params(delimiter: String, quoted: T::Boolean, strip: T::Boolean).void }
    def initialize(delimiter:, quoted:, strip:)
      @delimiter = delimiter
      @quoted = quoted
      @strip = strip
      @body = AST::Word.new([])
    end

    # The lexer fills the body — an AST::Word — once it has gathered the body
    # lines at the next newline; it is the only writer, so #body stays read-only.
    sig { params(body: AST::Word).void }
    def fill(body)
      @body = body
    end

    sig { returns(T::Array[AST::WordSegment]) }
    def segments
      @body.segments
    end
  end
end
