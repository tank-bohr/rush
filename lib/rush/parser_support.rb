# frozen_string_literal: true

module Rush
  # The body of the racc-generated Rush::Parser (its `---- inner` block only
  # `include`s this), kept in a normal linted/covered file. Rule actions call
  # these factories; none contain node logic.
  module ParserSupport
    def initialize(lexer)
      @lexer = lexer
    end

    def parse = do_parse

    def next_token = @lexer.next_token

    def on_error(token_id, value, _stack)
      near = value.respond_to?(:literal_text) ? value.literal_text : value
      raise ParseError, "syntax error at #{@lexer.location}: unexpected #{token_to_str(token_id)} `#{near}`"
    end

    private

    def make_list(entries)
      AST::List.new(entries.map { |and_or, sep| AST::ListEntry.new(and_or: and_or, async: sep == '&') })
    end

    def pending_entry(and_or) = [and_or, ';']

    def terminate_list(entries, sep)
      entries.last[1] = sep
      entries
    end

    def append_and_or(entries, sep, and_or)
      entries.last[1] = sep
      entries << [and_or, ';']
    end

    def make_and_or(left, op, right) = AST::AndOr.new(left, op, right)

    def make_pipeline(commands) = AST::Pipeline.new(commands)

    def make_simple_command(prefix, word, suffix)
      parts = prefix + [word].compact + suffix
      AST::SimpleCommand.new(parts.grep(AST::Assignment), parts.grep(AST::Word), parts.grep(AST::Redirect))
    end

    def make_redirect(kind, target) = AST::Redirect.new(kind: kind, target: target, io_number: nil)

    def with_io_number(redirect, number) = redirect.with(io_number: number)
  end
end
