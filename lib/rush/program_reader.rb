# typed: true
# frozen_string_literal: true

module Rush
  # Reads a shell source one line at a time, accumulating until the buffer parses
  # to a complete program. POSIX reads and executes command by command, so an
  # earlier command (a function definition, a future `alias`) can shape later
  # input and a syntax error only stops the commands that follow it — the ones
  # before it have already run. IncompleteInput means "the construct is
  # unfinished": pull another line (multi-line here-documents included). At end of
  # input a pending buffer gets one final, non-interactive parse so an
  # unterminated here-document still runs with the body so far, exactly like dash.
  class ProgramReader
    extend T::Sig

    sig do
      params(aliases: AliasTable,
             next_line: T.proc.params(buffered: T::Boolean).returns(T.nilable(String))).void
    end
    def initialize(aliases: AliasTable.new, &next_line)
      @next_line = next_line
      @aliases = aliases
      @buffer = +''
      @lines = SourceLineCounter.new
    end

    # The next complete program, or :eof. Raises ParseError on a real syntax
    # error, so the caller decides policy: batch aborts, the REPL reports and
    # resumes.
    sig { returns(T.any(AST::List, Symbol)) }
    def next_program
      @buffer = +''
      loop do
        outcome = read_more
        return outcome unless outcome == :more
      end
    end

    private

    sig { returns(T.any(AST::List, Symbol)) }
    def read_more
      line = @next_line.call(!@buffer.empty?)
      return finish unless line

      record_line(line)
      attempt(@buffer << line)
    end

    sig { params(line: String).void }
    def record_line(line)
      @buffer.empty? ? @lines.start(line) : @lines.continue(line)
    end

    sig { params(source: String).returns(T.any(AST::List, Symbol)) }
    def attempt(source)
      Parser.new(Lexer.new(source, interactive: true, aliases: @aliases, line_offset: @lines.offset)).parse
    rescue IncompleteInput
      :more
    end

    sig { returns(T.any(AST::List, Symbol)) }
    def finish
      return :eof if @buffer.empty?

      Parser.new(Lexer.new(@buffer, interactive: false, aliases: @aliases, line_offset: @lines.offset)).parse
    end
  end
end
