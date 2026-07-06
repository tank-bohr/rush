# typed: true
# frozen_string_literal: true

module Rush
  # Consumes the leading -/+ option clusters of an `sh` argv — the set-builtin
  # letters plus -c, -i, -s and `-o name`, ending at `--` or the first operand —
  # leaving the operands in place. Exposes the explicit option settings and
  # whether -c was given.
  class InvocationFlags
    extend T::Sig

    FLAGS = Options::LETTERS.merge('i' => :interactive, 's' => :stdin, 'l' => :login).freeze

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    attr_reader :settings

    sig { returns(T::Boolean) }
    attr_reader :command

    sig { params(argv: T::Array[String]).void }
    def initialize(argv)
      @settings = T.let({}, T::Hash[Symbol, T::Boolean])
      @command = T.let(false, T::Boolean)
      apply_cluster(T.must(argv.shift), argv) while cluster?(argv.first)
      argv.shift if argv.first == '--'
    end

    private

    sig { params(arg: T.nilable(String)).returns(T::Boolean) }
    def cluster?(arg)
      arg.is_a?(String) && arg.length > 1 && arg != '--' && arg.start_with?('-', '+')
    end

    sig { params(cluster: String, rest: T::Array[String]).void }
    def apply_cluster(cluster, rest)
      sign, *letters = cluster.chars
      letters.each { |letter| apply_letter(letter, T.must(sign), rest) }
    end

    sig { params(letter: String, sign: String, rest: T::Array[String]).void }
    def apply_letter(letter, sign, rest)
      case letter
      when 'c' then enable_command(sign)
      when 'o' then apply_long(sign, rest.shift)
      else apply_flag(letter, sign)
      end
    end

    sig { params(sign: String).void }
    def enable_command(sign)
      raise InvocationError, "Illegal option #{sign}c" unless sign == '-'

      @command = true
    end

    sig { params(sign: String, option_name: T.nilable(String)).void }
    def apply_long(sign, option_name)
      raise InvocationError, "#{sign}o requires an argument" unless option_name

      option = Options::LONG.fetch(option_name) do
        raise InvocationError, "Illegal option #{sign}o #{option_name}"
      end
      @settings[option] = sign == '-'
    end

    sig { params(letter: String, sign: String).void }
    def apply_flag(letter, sign)
      option = FLAGS.fetch(letter) { raise InvocationError, "Illegal option #{sign}#{letter}" }
      @settings[option] = sign == '-'
    end
  end

  # Parsed `sh` invocation: option flags (via InvocationFlags), then operands.
  # Picks the program input — -c command string, script file, or stdin — and
  # decides POSIX interactivity (-i, or no operands, no -c, and stdin and
  # stderr both attached to a terminal), building the session it all implies.
  class Invocation
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).void }
    def initialize(argv, system)
      @system = system
      rest = argv.dup
      @flags = T.let(InvocationFlags.new(rest), InvocationFlags)
      @operands = T.let(rest, T::Array[String])
      @input = T.let(build_input, T.any(CommandInput, ScriptInput, StdinInput))
    end

    # The session this invocation implies, wired to its shell state and
    # startup files (login profiles, interactive ENV).
    sig { returns(ProgramSession) }
    def session
      state = shell_state
      return Repl.new(@system, state: state, startup: startup) if repl?

      Source.new(self, @system, state: state, startup: startup)
    end

    sig { returns(T::Boolean) }
    def repl?
      interactive? && stdin_source?
    end

    sig { returns(T::Boolean) }
    def interactive?
      @flags.settings.fetch(:interactive) { auto_interactive? }
    end

    # A login shell: -l, or invoked with a leading '-' in the program name
    # (how login(1) execs a shell). dash accepts -l the same way; POSIX leaves
    # login files unspecified, so the oracle decides.
    sig { returns(T::Boolean) }
    def login?
      @flags.settings.fetch(:login) { @system.program_name.start_with?('-') }
    end

    sig { returns(String) }
    def name
      @input.name
    end

    sig { returns(T::Array[String]) }
    def positionals
      @input.positionals
    end

    # The option flags the session starts with: the explicit -/+ settings plus
    # the ones POSIX derives implicitly (s for a stdin source, i when
    # interactive), so $- reports them like dash does.
    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def shell_flags
      @flags.settings.merge(stdin: stdin_source?, interactive: interactive?)
    end

    # The program text (read lazily: a REPL session never gets here).
    sig { returns(String) }
    def source
      @input.source
    end

    private

    sig { returns(T.any(CommandInput, ScriptInput, StdinInput)) }
    def build_input
      return CommandInput.new(@operands) if @flags.command
      return StdinInput.new(@operands, @system) if stdin_source?

      ScriptInput.new(@operands, @system)
    end

    sig { returns(ShellState) }
    def shell_state
      state = ShellState.new(name: name, positional: positionals, pids: ShellProcessIds.for(@system))
      shell_flags.each { |option, enabled| state.set_option(option, enabled) }
      state
    end

    sig { returns(Startup) }
    def startup
      Startup.new(login: login?, interactive: interactive?)
    end

    # POSIX sh: with no -i, interactive only when reading stdin implicitly on a
    # terminal — no operands, and stdin and stderr both ttys. (-c with no
    # command string never gets to run: #source rejects it first.)
    sig { returns(T::Boolean) }
    def auto_interactive?
      @operands.empty? && @system.tty? && @system.stderr_tty?
    end

    sig { returns(T::Boolean) }
    def stdin_source?
      return false if @flags.command

      @flags.settings.fetch(:stdin) { @operands.empty? }
    end
  end
end
