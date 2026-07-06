# typed: true
# frozen_string_literal: true

module Rush
  # The interactive prompt strings (POSIX 2.5.3): PS1 and PS2 are re-read from
  # the shell variables at every prompt — so assignments take effect
  # mid-session — and subjected to parameter expansion ONLY (via ParamText).
  # Defaults: '$ ' ('# ' for a privileged shell) and '> '. A malformed value
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
