# frozen_string_literal: true

module Rush
  # Lexical loop nesting for break/continue: the count of for/while/until loops
  # enclosing the current command in the same execution environment. A function
  # call or subshell starts fresh (#without), so a break inside a function cannot
  # reach the caller's loop, while dot/eval/group bodies run inline and keep the
  # count. break/continue read #depth to clamp their level and #any? to no-op
  # when there is no enclosing loop.
  class LoopNesting
    attr_reader :depth

    def initialize
      @depth = 0
    end

    def enter
      @depth += 1
    end

    def leave
      @depth -= 1
    end

    def any?
      @depth.positive?
    end

    def without
      saved = @depth
      @depth = 0
      yield
    ensure
      @depth = saved
    end
  end
end
