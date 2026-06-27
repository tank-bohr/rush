# frozen_string_literal: true

require 'strscan'
require_relative 'lexer/operator_table'
require_relative 'lexer/lex_state'
require_relative 'lexer/substitution_reader'
require_relative 'lexer/word_scanner'
require_relative 'lexer/heredoc_body'
require_relative 'lexer/token_classifier'

module Rush
  # StringScanner pump that yields [symbol, value] pairs for racc. It skips
  # blanks and comments, then emits NEWLINE, an IO_NUMBER, an operator, or a
  # WORD/ASSIGNMENT_WORD (classified against LexState, which advances after each
  # token to track command position — the seed of POSIX Grammar Rules 1-9).
  class Lexer
    BLANK = /[ \t]+/
    COMMENT = /#[^\n]*/
    IO_NUMBER = /\d+(?=[<>])/
    HEREDOC_OPS = { DLESS: :plain, DLESSDASH: :strip }.freeze

    def initialize(source)
      @scanner = StringScanner.new(source)
      @state = LexState.new
      @awaiting = nil
      @heredocs = []
    end

    def location = @scanner.charpos

    def next_token
      skip_insignificant
      return [false, false] if @scanner.eos?

      emit(scan_token)
    end

    private

    def emit(token)
      @state.advance(token.first)
      token
    end

    def skip_insignificant
      loop { break unless @scanner.skip(BLANK) || @scanner.skip(COMMENT) }
    end

    def scan_token
      return heredoc_newline if @scanner.scan("\n")

      io_number || operator || word
    end

    def io_number
      digits = @scanner.scan(IO_NUMBER)
      digits && [:IO_NUMBER, digits.to_i]
    end

    def operator
      matched = @scanner.scan(OperatorTable::PATTERN)
      matched && operator_token(matched)
    end

    def operator_token(matched)
      symbol = OperatorTable::OPERATORS[matched]
      @awaiting = HEREDOC_OPS[symbol]
      [symbol, matched]
    end

    def word
      token = TokenClassifier.new(WordScanner.new(@scanner).scan, @state).call
      @awaiting ? delimiter(token.last) : token
    end

    def delimiter(word)
      holder = HereDoc.new(delimiter: word.segments.map(&:value).join,
                           quoted: word.segments.any?(&:quoted), strip: @awaiting == :strip)
      @awaiting = nil
      @heredocs << holder
      [:WORD, holder]
    end

    # On the newline that ends the command line, drain the pending here-docs:
    # read each body from the lines that follow, in the order the `<<`s appeared.
    def heredoc_newline
      @heredocs.each { |holder| holder.body = read_heredoc(holder) }
      @heredocs = []
      [:NEWLINE, "\n"]
    end

    def read_heredoc(holder) = build_body(holder, gather(holder, +''))

    def gather(holder, out)
      line = heredoc_line(holder)
      return out if line.nil?

      gather(holder, out << line)
    end

    def heredoc_line(holder)
      line = @scanner.scan(/[^\n]*\n?/)
      return nil if line.to_s.empty? || delimiter?(holder, line)

      strip_tabs(holder, line)
    end

    def delimiter?(holder, line) = strip_tabs(holder, line).chomp == holder.delimiter

    def strip_tabs(holder, line) = holder.strip ? line.sub(/\A\t+/, '') : line

    # A quoted delimiter (<<'EOF') makes the body literal; an unquoted one is
    # parsed for expansion ($var, $(...), `...`), applied later at execution.
    def build_body(holder, text)
      return literal_word(text) if holder.quoted

      HeredocBody.new(text).scan
    end

    def literal_word(text) = AST::Word.new([AST::WordSegment.new(kind: :literal, value: text, quoted: false)])
  end
end
