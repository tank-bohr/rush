# typed: true
# frozen_string_literal: true

module Rush
  # Tracks absolute source line numbers while ProgramReader buffers one complete
  # program. Each Lexer sees only the current buffer, so the counter supplies the
  # offset that makes word/source-line metadata absolute within the caller's
  # source stream.
  class SourceLineCounter
    extend T::Sig

    sig { void }
    def initialize
      @line_number = 0
      @buffer_start = 1
    end

    sig { params(line: String).void }
    def start(line)
      @buffer_start = @line_number + 1
      advance(line)
    end

    sig { params(line: String).void }
    def continue(line)
      advance(line)
    end

    sig { returns(Integer) }
    def offset
      @buffer_start - 1
    end

    private

    sig { params(line: String).void }
    def advance(line)
      @line_number += line.each_line.count
    end
  end
end
