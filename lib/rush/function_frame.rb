# typed: true
# frozen_string_literal: true

module Rush
  # Brackets a shell-function invocation: open a local-variable scope, reset loop
  # nesting so break/continue cannot escape to the caller, bind positional
  # parameters to the function arguments, then restore all three on return.
  class FunctionFrame
    extend T::Sig

    sig { params(variables: ShellVariables, loops: LoopNesting, positional: Positional).void }
    def initialize(variables:, loops:, positional:)
      @variables = variables
      @loops = loops
      @positional = positional
    end

    sig do
      type_parameters(:U)
        .params(args: T::Array[String], blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def call(args, &blk)
      @variables.begin_scope
      @loops.without { @positional.with(args, &blk) }
    ensure
      @variables.end_scope
    end
  end
end
