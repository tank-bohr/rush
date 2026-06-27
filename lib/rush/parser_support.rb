# frozen_string_literal: true

module Rush
  # The body of the racc-generated Rush::Parser. Its `---- inner` block only
  # `include`s this module, so the delegate, error handler and AST factories
  # live in a normal, linted and covered file rather than inside the generated
  # parser. Rule actions call these factories and contain no node logic.
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

    def make_sequence(commands) = AST::Sequence.new(commands)

    def make_simple_command(words) = AST::SimpleCommand.new(words)
  end
end
