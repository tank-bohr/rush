# typed: true
# frozen_string_literal: true

require 'strscan'
require_relative 'lexer/operator_table'
require_relative 'lexer/lex_state'
require_relative 'lexer/source_lines'
require_relative 'lexer/scanner_predicates'
require_relative 'lexer/token_predicates'
require_relative 'lexer/quote_skips'
require_relative 'lexer/case_frame'
require_relative 'lexer/case_tracker'
require_relative 'lexer/paren_regions'
require_relative 'lexer/paren_reader'
require_relative 'lexer/substitution_reader'
require_relative 'lexer/braced_reader'
require_relative 'lexer/param_scanner'
require_relative 'lexer/quoted_word'
require_relative 'lexer/dollar_scanner'
require_relative 'lexer/double_quote_scanner'
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
  # Exact token aliases keep the Racc boundary local; the cohesive scanner stays
  # above the generic class-length threshold rather than being split around them.
  # rubocop:disable Metrics/ClassLength
  class Lexer
    extend T::Sig
    include TokenPredicates

    TokenKind = T.type_alias { T.any(Symbol, String) }
    TokenValue = T.type_alias { T.any(AST::Word, AST::Assignment, HereDoc, String, Integer) }
    Token = T.type_alias { [TokenKind, TokenValue] }
    NextToken = T.type_alias { T.any(Token, [FalseClass, FalseClass]) }

    # Between tokens, blanks, comments and backslash-newline continuations
    # (POSIX 2.2.1) are all insignificant. A continuation at the buffer's very
    # end is left for the word scanner, which asks for the next line instead
    # of ending the token stream.
    INSIGNIFICANT = /(?:[ \t]+|#[^\n]*|\\\n(?=.))+/m
    # "Immediately before < or >" sees through spliced continuations, like the
    # operator matcher: dash-verified, `2\<newline>>f` redirects fd 2.
    IO_NUMBER = /\d+(?=(?:\\\n)*[<>])/
    HEREDOC_OPS = T.let(
      { DLESS: :plain, DLESSDASH: :strip }.freeze,
      T::Hash[T.any(Symbol, String), Symbol]
    )

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
      scanner.charpos
    end

    sig { returns(NextToken) }
    def next_token
      drain
      return [false, false] if scanner.eos?

      token = scan_token
      token ? emit(token) : next_token
    end

    private

    sig { returns(StringScanner) }
    attr_accessor :scanner

    sig { returns(AliasExpander) }
    attr_reader :aliases

    sig { returns(T::Boolean) }
    attr_reader :interactive

    sig { returns(LexState) }
    attr_reader :state

    sig { returns(SourceLines) }
    attr_reader :lines

    sig { returns(T.nilable(Symbol)) }
    attr_accessor :awaiting

    sig { returns(T::Array[HereDoc]) }
    attr_accessor :heredocs

    sig { params(token: Token).returns(Token) }
    def emit(token)
      state.advance(token.first)
      aliases.spend
      token
    end

    # Skip blanks and comments; when the current frame is an exhausted alias
    # replacement, restore the input beneath it and keep skipping.
    sig { void }
    def drain
      skip_insignificant
      return unless scanner.eos? && aliases.nested?

      self.scanner = T.must(aliases.pop)
      drain
    end

    sig { void }
    def skip_insignificant
      scanner.skip(INSIGNIFICANT)
    end

    sig { returns(T.nilable(Token)) }
    def scan_token
      return heredoc_newline if scanner.scan("\n")

      io_number || operator || word
    end

    sig { returns(T.nilable(Token)) }
    def io_number
      digits = scanner.scan(IO_NUMBER)
      digits ? [:IO_NUMBER, Integer(digits, 10)] : nil
    end

    sig { returns(T.nilable(Token)) }
    def operator
      matched = scanner.scan(OperatorTable::PATTERN)
      matched ? operator_token(matched) : nil
    end

    # The match may carry line continuations between its characters (see
    # OperatorTable::PATTERN); splicing them out recovers the operator.
    sig { params(matched: String).returns(Token) }
    def operator_token(matched)
      operator = matched.gsub(OperatorTable::CONTINUATION, '')
      symbol = OperatorTable::OPERATORS.fetch(operator)
      self.awaiting = HEREDOC_OPS.fetch(symbol, nil)
      [symbol, operator]
    end

    # A word awaited as a here-document delimiter is taken raw — never
    # classified, aliased or reserved. Otherwise classify it, then (only a
    # plain WORD) splice its alias replacement in its place; a splice returns
    # nil so next_token re-reads from the new frame.
    sig { returns(T.nilable(Token)) }
    def word
      scanned = lines.word { WordScanner.next_word(scanner, interactive: interactive) }
      return delimiter(scanned) if awaiting

      token = TokenClassifier.new(scanned, state).call
      replacement = alias_for(token, scanned)
      replacement ? splice(replacement) : token
    end

    sig { params(token: Token, word: AST::Word).returns(T.nilable(AliasExpander::Replacement)) }
    def alias_for(token, word)
      return if !word_token?(token) || !state.command_mode?

      aliases.expand(word, state.expects_command?)
    end

    sig { params(replacement: AliasExpander::Replacement).returns(NilClass) }
    def splice(replacement)
      aliases.push(replacement, scanner)
      self.scanner = StringScanner.new(replacement.value)
      nil
    end

    sig { params(word: AST::Word).returns(Token) }
    def delimiter(word)
      holder = HereDoc.new(delimiter: delimiter_text(word), quoted: delimiter_quoted?(word),
                           strip: awaiting == :strip, source_line: word.source_line)
      self.awaiting = nil
      heredocs << holder
      [:WORD, holder]
    end

    sig { params(word: AST::Word).returns(String) }
    def delimiter_text(word)
      word.segments.map(&:value).join
    end

    sig { params(word: AST::Word).returns(T::Boolean) }
    def delimiter_quoted?(word)
      word.segments.any?(&:quoted)
    end

    # On the newline that ends the command line, drain the pending here-docs:
    # read each body from the lines that follow, in the order the `<<`s appeared.
    sig { returns(Token) }
    def heredoc_newline
      start = scanner.pos
      HeredocReader.new(scanner, interactive: interactive).fill(heredocs)
      self.heredocs = []
      lines.heredoc_newline(start)
      [:NEWLINE, "\n"]
    end
  end
  # rubocop:enable Metrics/ClassLength
end
