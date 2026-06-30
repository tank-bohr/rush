# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # Evaluates an already parameter-expanded arithmetic string: tokenize,
      # parse, walk the AST. A bare name resolves to its shell value parsed as an
      # integer constant (unset or blank is 0); a non-numeric value is an error,
      # as in dash. Recursion into a value as an *expression* is not done.
      class Evaluator
        extend T::Sig

        sig { params(executor: Executor).void }
        def initialize(executor)
          @executor = executor
        end

        sig { params(source: String).returns(Integer) }
        def evaluate(source)
          Parser.new(Tokenizer.new(source).tokens).parse.result(self)
        end

        sig { params(name: String).returns(Integer) }
        def resolve(name)
          value = @executor.state.environment.get(name)
          return 0 if value.to_s.strip.empty?

          Number.parse(value)
        end

        # `name op= value`: for a compound operator, combine with the current
        # value first (`+=` -> `+`); store the wrapped result and return it.
        sig { params(name: String, op: String, value: Integer).returns(Integer) }
        def assign(name, op, value)
          result = op == '=' ? value : Number.binary(op[0..-2], resolve(name), value)
          @executor.state.environment.assign(name, result.to_s)
          result
        end
      end
    end
  end
end
