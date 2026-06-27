# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # Evaluates an already parameter-expanded arithmetic string: tokenize,
      # parse, walk the AST. A bare name resolves to its shell value parsed as an
      # integer constant (unset or blank is 0); a non-numeric value is an error,
      # as in dash. Recursion into a value as an *expression* is not done.
      class Evaluator
        def initialize(executor)
          @executor = executor
        end

        def evaluate(source) = Parser.new(Tokenizer.new(source).tokens).parse.result(self)

        def resolve(name)
          value = @executor.state.environment.get(name)
          return 0 if value.nil? || value.strip.empty?

          Number.parse(value)
        end

        # `name op= value`: for a compound operator, combine with the current
        # value first (`+=` -> `+`); store the wrapped result and return it.
        def assign(name, op, value)
          result = op == '=' ? value : Number.binary(op[0..-2], resolve(name), value)
          @executor.state.environment.assign(name, result.to_s)
          result
        end
      end
    end
  end
end
