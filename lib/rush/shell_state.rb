# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, the shell name ($0), the logical working directory, the
  # positional parameters and the function table. The executor backfills pwd from
  # the OS when the environment has no PWD.
  class ShellState
    attr_reader :environment, :functions, :traps, :aliases, :loop_depth, :command_hash, :name
    attr_accessor :last_status, :pwd, :positional

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @name = name
      @pwd = environment.get('PWD')
      @traps = TrapTable.new
      initialize_runtime
    end

    # Shell options set by `set -o`-style flags (:nounset, :xtrace, ...).
    def set_option(name, enabled) = enabled ? @options.add(name) : @options.delete(name)

    def option?(name) = @options.include?(name)

    # Dynamic `local` scope: a function call brackets its body with
    # begin/end_scope; declare_local snapshots a variable so end_scope restores
    # its prior value (or unsets it when it had none).
    def begin_scope = @scopes.push({})

    def end_scope = @scopes.pop.each { |name, value| restore(name, value) }

    def in_function? = @scopes.any?

    def declare_local(name)
      frame = @scopes.last
      frame[name] = @environment.get(name) unless frame.key?(name)
    end

    # Lexical loop nesting for break/continue. The depth counts the for/while/
    # until loops enclosing the current command within the same execution
    # environment; a function call or subshell starts fresh (without_loops), so a
    # break inside a function cannot reach the caller's loop, while dot/eval/group
    # bodies run inline and keep the count. break/continue read it to clamp their
    # level and to no-op when there is no enclosing loop.
    def enter_loop = @loop_depth += 1

    def leave_loop = @loop_depth -= 1

    def in_loop? = @loop_depth.positive?

    def without_loops
      saved = @loop_depth
      @loop_depth = 0
      yield
    ensure
      @loop_depth = saved
    end

    private

    def restore(name, value)
      value ? @environment.assign(name, value) : @environment.unset(name)
    end

    def initialize_runtime
      @last_status = Status.success
      @positional = []
      @options = Set.new
      build_runtime
    end

    def build_runtime
      @scopes = []
      @loop_depth = 0
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end
  end
end
