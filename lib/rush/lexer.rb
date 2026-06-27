# frozen_string_literal: true

require 'strscan'
require_relative 'lexer/operator_table'
require_relative 'lexer/lex_state'
require_relative 'lexer/substitution_reader'
require_relative 'lexer/word_scanner'
require_relative 'lexer/heredoc_body'
require_relative 'lexer/token_classifier'
require_relative 'lexer/alias_expander'

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

    def initialize(source, interactive: false, aliases: nil)
      @scanner = StringScanner.new(source)
      @aliases = AliasExpander.new(aliases)
      @interactive = interactive
      init_state
    end

    def location = @scanner.charpos

    def next_token
      drain
      return [false, false] if @scanner.eos?

      token = scan_token
      token ? emit(token) : next_token
    end

    private

    def init_state
      @state = LexState.new
      @awaiting = nil
      @heredocs = []
    end

    def emit(token)
      @state.advance(token.first)
      @aliases.spend
      token
    end

    # Skip blanks and comments; when the current frame is an exhausted alias
    # replacement, restore the input beneath it and keep skipping.
    def drain
      skip_insignificant
      return unless @scanner.eos? && @aliases.nested?

      @scanner = @aliases.pop
      drain
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

    # Classify the word, then (only a plain WORD, never a reserved word or a
    # here-document delimiter) splice its alias replacement in its place; a splice
    # returns nil so next_token re-reads from the new frame.
    def word
      scanned = WordScanner.new(@scanner).scan
      token = TokenClassifier.new(scanned, @state).call
      value = alias_for(token, scanned)
      value ? splice(value) : finish(token)
    end

    def alias_for(token, word)
      return nil if @awaiting || token.first != :WORD || !@state.command_mode?

      @aliases.expand(word, @state.expects_command?)
    end

    def splice(value)
      @aliases.push(@scanner)
      @scanner = StringScanner.new(value)
      nil
    end

    def finish(token) = @awaiting ? delimiter(token.last) : token

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
      raise IncompleteInput, 'unterminated here-document' if line.to_s.empty? && @interactive
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
