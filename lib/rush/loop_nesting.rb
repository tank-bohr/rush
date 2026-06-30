# typed: true
# frozen_string_literal: true

module Rush
  # Lexical loop nesting for break/continue: the count of for/while/until loops
  # enclosing the current command in the same execution environment. A function
  # call or subshell starts fresh (#without), so a break inside a function cannot
  # reach the caller's loop, while dot/eval/group bodies run inline and keep the
  # count. break/continue read #depth to clamp their level and #any? to no-op
  # when there is no enclosing loop.
  class LoopNesting
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :depth

    sig { void }
    def initialize
      @depth = 0
    end

    sig { void }
    def enter
      @depth += 1
    end

    sig { void }
    def leave
      @depth -= 1
    end

    sig { returns(T::Boolean) }
    def any?
      @depth.positive?
    end

    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def without(&blk) # rubocop:disable Naming/BlockForwarding
      saved = T.let(@depth, Integer)
      @depth = 0
      yield
    ensure
      @depth = T.must(saved)
    end
  end
end
