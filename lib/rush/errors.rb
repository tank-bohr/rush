# frozen_string_literal: true

module Rush
  # Base class for every error rush raises.
  class Error < StandardError; end

  # Raised by the parser on a syntax error (carries a human-readable location).
  class ParseError < Error; end

  # Parsing hit end of input mid-construct (an unfinished quote, compound
  # command or here-document). A ParseError subclass, so batch callers still
  # treat it as a syntax error; the REPL catches it to read another line.
  class IncompleteInput < ParseError; end

  # Raised during word expansion (e.g. ${x:?msg}, bad substitution).
  class ExpansionError < Error; end

  # Raised by the `test`/`[` builtin on a malformed expression (mapped to exit 2).
  class TestError < Error; end

  # Raised when assigning to or unsetting a readonly variable; like dash, this
  # aborts the script (or just the subshell) with exit status 2.
  class ReadonlyError < Error; end

  # A special builtin used incorrectly (e.g. a non-numeric operand to
  # exit/return). POSIX 2.8.1: such an error aborts a non-interactive shell with
  # status 2; interactively it is reported and the shell carries on.
  class BuiltinError < Error; end

  # A redirection that fails at runtime (e.g. `n>&m` duplicating a fd that is not
  # open): the command is not run and fails with status 2, but — unlike a
  # special-builtin error — the shell carries on.
  class RedirectError < Error; end

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
