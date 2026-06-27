# frozen_string_literal: true

module Rush
  # Base class for every error rush raises.
  class Error < StandardError; end

  # Raised by the parser on a syntax error (carries a human-readable location).
  class ParseError < Error; end

  # Raised during word expansion (e.g. ${x:?msg}, bad substitution).
  class ExpansionError < Error; end

  # Control-flow signal: `exit` unwinds to the top level carrying a status code.
  class ExitSignal < Error
    attr_reader :code

    def initialize(code)
      @code = code
      super("exit #{code}")
    end
  end

  # Loop control: `break`/`continue` unwind to the enclosing loop, carrying the
  # number of loop levels to act on.
  class LoopControl < Error
    attr_reader :count

    def initialize(count)
      @count = count
      super('loop control')
    end
  end

  class BreakSignal < LoopControl; end
  class ContinueSignal < LoopControl; end

  # Control-flow signal: `return` unwinds to the enclosing function call.
  class ReturnSignal < Error
    attr_reader :code

    def initialize(code)
      @code = code
      super("return #{code}")
    end
  end
end
