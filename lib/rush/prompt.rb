# typed: true
# frozen_string_literal: true

module Rush
  # The prompt strings (POSIX 2.5.3): PS1, PS2 and the PS4 trace prefix are
  # re-read from the shell variables at every use — so assignments take effect
  # mid-session — and subjected to parameter expansion ONLY (via ParamText),
  # so a PS4 holding $(cmd) or backticks stays literal and tracing can never
  # recurse into command execution (dash strips backticks unexecuted, errors
  # $(cmd) back to the raw string, and expands only $((arith)) — POSIX's
  # parameter-expansion-only text wins). Defaults:
  # '$ ' ('# ' for a privileged shell), '> ' and '+ '. A malformed value
  # (unterminated ${, a failing ${x?} form) falls back to the raw string: a
  # prompt must never break the session.
  class Prompt
    extend T::Sig

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
    end

    sig { returns(String) }
    def primary
      render('PS1', @executor.system.privileged? ? '# ' : '$ ')
    end

    sig { returns(String) }
    def continuation
      render('PS2', '> ')
    end

    sig { returns(String) }
    def trace
      render('PS4', '+ ')
    end

    private

    sig { params(name: String, default: String).returns(String) }
    def render(name, default)
      expand(@executor.state.variables.get(name) || default)
    end

    sig { params(raw: String).returns(String) }
    def expand(raw)
      @executor.expander.expand_value(ParamText.new(raw).word, tilde: :none)
    rescue ParseError, ExpansionError
      raw
    end
  end
end
