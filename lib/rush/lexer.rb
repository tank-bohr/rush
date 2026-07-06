# typed: true
# frozen_string_literal: true

require 'strscan'
require_relative 'lexer/operator_table'
require_relative 'lexer/lex_state'
require_relative 'lexer/source_lines'
require_relative 'lexer/scanner_predicates'
require_relative 'lexer/token_predicates'
require_relative 'lexer/substitution_reader'
require_relative 'lexer/param_scanner'
require_relative 'lexer/dollar_scanner'
require_relative 'lexer/word_scanner'
require_relative 'lexer/heredoc_body'
require_relative 'lexer/heredoc_reader'
require_relative 'lexer/token_classifier'
require_relative 'lexer/alias_expander'

module Rush
  # StringScanner pump that yields [symbol, value] pairs for racc. It skips
  # blanks and comments, then emits NEWLINE, an IO_NUMBER, an operator, or a
  # WORD/ASSIGNMENT_WORD (classified against LexState, which advances after each
  # token to track command position — the seed of POSIX Grammar Rules 1-9).
  class Lexer
    extend T::Sig
    include TokenPredicates

    # Between tokens, blanks, comments and backslash-newline continuations
    # (POSIX 2.2.1) are all insignificant. A continuation at the buffer's very
    # end is left for the word scanner, which asks for the next line instead
    # of ending the token stream.
    INSIGNIFICANT = /(?:[ \t]+|#[^\n]*|\\\n(?=.))+/m
    IO_NUMBER = /\d+(?=[<>])/
    HEREDOC_OPS = { DLESS: :plain, DLESSDASH: :strip }.freeze

    sig { params(source: String, interactive: T::Boolean, aliases: T.nilable(AliasTable), line_offset: Integer).void }
    def initialize(source, interactive: false, aliases: nil, line_offset: 0)
      @scanner = StringScanner.new(source)
      @aliases = AliasExpander.new(aliases)
      @interactive = interactive
      @state = LexState.new
      @lines = SourceLines.new(@scanner, line_offset)
      @awaiting = nil
      @heredocs = []
    end

    sig { returns(Integer) }
    def location
      @scanner.charpos
    end

    sig { returns([T.untyped, T.untyped]) }
    def next_token
      drain
      return [false, false] if @scanner.eos?

      token = scan_token
      token ? emit(token) : next_token
    end

    private

    sig { params(token: [T.untyped, T.untyped]).returns([T.untyped, T.untyped]) }
    def emit(token)
      @state.advance(token.first)
      @aliases.spend
      token
    end

    # Skip blanks and comments; when the current frame is an exhausted alias
    # replacement, restore the input beneath it and keep skipping.
    sig { void }
    def drain
      skip_insignificant
      return unless @scanner.eos? && @aliases.nested?

      @scanner = @aliases.pop
      drain
    end

    sig { void }
    def skip_insignificant
      @scanner.skip(INSIGNIFICANT)
    end

    sig { returns(T.nilable([T.untyped, T.untyped])) }
    def scan_token
      return heredoc_newline if @scanner.scan("\n")

      io_number || operator || word
    end

    sig { returns(T.nilable([T.untyped, T.untyped])) }
    def io_number
      digits = @scanner.scan(IO_NUMBER)
      digits ? [:IO_NUMBER, Integer(digits, 10)] : nil
    end

    sig { returns(T.nilable([T.untyped, T.untyped])) }
    def operator
      matched = @scanner.scan(OperatorTable::PATTERN)
      matched ? operator_token(matched) : nil
    end

    sig { params(matched: String).returns([T.untyped, T.untyped]) }
    def operator_token(matched)
      symbol = OperatorTable::OPERATORS.fetch(matched)
      @awaiting = HEREDOC_OPS.fetch(symbol, nil)
      [symbol, matched]
    end

    # Classify the word, then (only a plain WORD, never a reserved word or a
    # here-document delimiter) splice its alias replacement in its place; a splice
    # returns nil so next_token re-reads from the new frame.
    sig { returns(T.nilable([T.untyped, T.untyped])) }
    def word
      scanned = @lines.word { WordScanner.next_word(@scanner, interactive: @interactive) }
      token = TokenClassifier.new(scanned, @state).call
      replacement = alias_for(token, scanned)
      return splice(replacement) if replacement

      @awaiting ? delimiter(token.last) : token
    end

    sig { params(token: [T.untyped, T.untyped], word: AST::Word).returns(T.nilable(AliasExpander::Replacement)) }
    def alias_for(token, word)
      return if @awaiting || !word_token?(token) || !@state.command_mode?

      @aliases.expand(word, @state.expects_command?)
    end

    sig { params(replacement: AliasExpander::Replacement).returns(NilClass) }
    def splice(replacement)
      @aliases.push(replacement, @scanner)
      @scanner = StringScanner.new(replacement.value)
      nil
    end

    sig { params(word: T.untyped).returns([T.untyped, T.untyped]) }
    def delimiter(word)
      holder = HereDoc.new(delimiter: word.segments.map(&:value).join,
                           quoted: word.segments.any?(&:quoted), strip: @awaiting == :strip,
                           source_line: word.source_line)
      @awaiting = nil
      @heredocs << holder
      [:WORD, holder]
    end

    # On the newline that ends the command line, drain the pending here-docs:
    # read each body from the lines that follow, in the order the `<<`s appeared.
    sig { returns([T.untyped, T.untyped]) }
    def heredoc_newline
      start = @scanner.pos
      HeredocReader.new(@scanner, interactive: @interactive).fill(@heredocs)
      @heredocs = []
      @lines.heredoc_newline(start)
      [:NEWLINE, "\n"]
    end
  end
end
