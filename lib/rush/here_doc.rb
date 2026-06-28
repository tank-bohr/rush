# frozen_string_literal: true

module Rush
  # A here-document redirect target. The lexer creates it when it sees `<<word`
  # (recording the delimiter, whether it was quoted, and the `<<-` tab strip),
  # then fills #body — an AST::Word — once it collects the body lines at the next
  # newline. It quacks like a Word (responds to #segments) so the expansion
  # pipeline expands the body as a single field at execution time.
  class HereDoc
    attr_reader :body, :delimiter, :quoted, :strip

    def initialize(delimiter:, quoted:, strip:)
      @delimiter = delimiter
      @quoted = quoted
      @strip = strip
      @body = AST::Word.new([])
    end

    # The lexer fills the body — an AST::Word — once it has gathered the body
    # lines at the next newline; it is the only writer, so #body stays read-only.
    def fill(body) = @body = body

    def segments = @body.segments
  end
end
