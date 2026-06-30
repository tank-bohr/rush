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
          # .to_s at the source coerces the nilable shell value (unset -> "") once,
          # so `value` is a String downstream and Number.parse can take a real String
          # rather than untyped — without an extra `value` reference that trips reek.
          value = @executor.state.environment.get(name).to_s
          return 0 if value.strip.empty?

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
