# typed: true
# frozen_string_literal: true

module Rush
  # The body of the racc-generated Rush::Parser (its `---- inner` block only
  # `include`s this), kept in a normal linted/covered file. Rule actions call
  # these factories; none contain node logic.
  # Factory contracts make the generated parser's hand-written host intentionally explicit.
  # rubocop:disable Metrics/ModuleLength
  module ParserSupport
    extend T::Sig

    ListEntry = T.type_alias { [AST::Node, String] }
    CommandPart = T.type_alias { T.any(AST::Assignment, AST::Word, AST::Redirect) }
    TokenKind = T.type_alias { T.any(Symbol, String) }
    TokenValue = T.type_alias { T.any(AST::Word, AST::Assignment, HereDoc, String, Integer) }
    ErrorValue = T.type_alias { T.any(AST::Assignment, HereDoc, String, Integer, FalseClass) }
    Token = T.type_alias { T.any([TokenKind, TokenValue], [FalseClass, FalseClass]) }

    sig { params(lexer: Lexer).void }
    def initialize(lexer)
      @lexer = T.let(lexer, Lexer)
    end

    sig { returns(AST::List) }
    def parse
      T.cast(do_parse, AST::List)
    end

    sig { returns(Token) }
    def next_token
      @lexer.next_token
    end

    sig { params(token_id: Integer, value: T.any(TokenValue, FalseClass), _stack: T.untyped).returns(T.noreturn) }
    def on_error(token_id, value, _stack)
      Kernel.raise IncompleteInput, 'unexpected end of input' if value == false

      near = error_value(value)
      Kernel.raise ParseError,
                   "syntax error at #{@lexer.location}: unexpected #{token_to_str(token_id)} `#{near}`"
    end

    private

    sig { params(value: T.any(TokenValue, FalseClass)).returns(ErrorValue) }
    def error_value(value)
      value.is_a?(AST::Word) ? value.literal_text : value
    end

    sig { params(entries: T::Array[ListEntry]).returns(AST::List) }
    def make_list(entries)
      AST::List.new(entries.map { |and_or, sep| AST::ListEntry.new(and_or: and_or, async: sep == '&') })
    end

    sig { params(and_or: AST::Node).returns(ListEntry) }
    def pending_entry(and_or)
      [and_or, ';']
    end

    sig { params(entries: T::Array[ListEntry], sep: String).returns(T::Array[ListEntry]) }
    def terminate_list(entries, sep)
      T.must(entries.last)[1] = sep
      entries
    end

    sig do
      params(entries: T::Array[ListEntry], sep: String, and_or: AST::Node).returns(T::Array[ListEntry])
    end
    def append_and_or(entries, sep, and_or)
      T.must(entries.last)[1] = sep
      entries << [and_or, ';']
    end

    sig { params(left: AST::Node, op: Symbol, right: AST::Node).returns(AST::AndOr) }
    def make_and_or(left, op, right)
      AST::AndOr.new(left, op, right)
    end

    sig { params(commands: T::Array[AST::Node], negate: T::Boolean).returns(AST::Pipeline) }
    def make_pipeline(commands, negate)
      AST::Pipeline.new(commands, negate)
    end

    sig do
      params(condition: AST::Node, consequent: AST::Node, alternative: T.nilable(AST::Node)).returns(AST::If)
    end
    def make_if(condition, consequent, alternative)
      AST::If.new(condition, consequent, alternative)
    end

    sig { params(body: AST::Node).returns(AST::BraceGroup) }
    def make_brace_group(body)
      AST::BraceGroup.new(body)
    end

    sig { params(body: AST::Node).returns(AST::Subshell) }
    def make_subshell(body)
      AST::Subshell.new(body)
    end

    sig { params(command: AST::Node, redirects: T::Array[AST::Redirect]).returns(AST::Redirected) }
    def make_redirected(command, redirects)
      AST::Redirected.new(command, redirects)
    end

    sig { params(condition: AST::Node, body: AST::Node).returns(AST::While) }
    def make_while(condition, body)
      AST::While.new(condition, body)
    end

    sig { params(condition: AST::Node, body: AST::Node).returns(AST::Until) }
    def make_until(condition, body)
      AST::Until.new(condition, body)
    end

    sig { params(name: String, words: T.nilable(T::Array[AST::Word]), body: AST::Node).returns(AST::For) }
    def make_for(name, words, body)
      AST::For.new(name, words, body)
    end

    sig { params(word: AST::Word, items: T::Array[AST::CaseItem]).returns(AST::Case) }
    def make_case(word, items)
      AST::Case.new(word, items)
    end

    sig { params(patterns: T::Array[AST::Word], body: AST::Node).returns(AST::CaseItem) }
    def make_case_item(patterns, body)
      AST::CaseItem.new(patterns: patterns, body: body)
    end

    sig { params(word: AST::Word, body: AST::Node).returns(AST::FunctionDef) }
    def make_function(word, body)
      AST::FunctionDef.new(word.literal_text, body)
    end

    sig do
      params(prefix: T::Array[CommandPart], word: T.nilable(AST::Word), suffix: T::Array[CommandPart])
        .returns(AST::SimpleCommand)
    end
    def make_simple_command(prefix, word, suffix)
      AST::SimpleCommand.new(prefix + [word].compact + suffix)
    end

    sig { params(kind: Symbol, target: AST::Word).returns(AST::Redirect) }
    def make_redirect(kind, target)
      AST::Redirect.new(kind: kind, target: target, io_number: nil)
    end

    sig { params(holder: HereDoc).returns(AST::Redirect) }
    def make_heredoc(holder)
      AST::Redirect.new(kind: :heredoc, target: holder, io_number: nil)
    end

    sig { params(redirect: AST::Redirect, number: Integer).returns(AST::Redirect) }
    def with_io_number(redirect, number)
      redirect.with(io_number: number)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
