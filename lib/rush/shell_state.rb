# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, the shell name ($0), the variable scope (local scoping and
  # the logical cwd, off in Scope), the positional parameters and the function
  # table. The executor backfills pwd from the OS when the environment has no PWD.
  class ShellState
    attr_reader :environment, :functions, :traps, :aliases, :loop_depth, :command_hash, :name, :scope,
                :last_status, :positional

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @name = name
      @scope = Scope.new(environment)
      @traps = TrapTable.new
      @last_status = Status.success
      @positional = []
      @options = Set.new
      @loop_depth = 0
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end

    # Shell options set by `set -o`-style flags (:nounset, :xtrace, ...).
    def set_option(name, enabled) = enabled ? @options.add(name) : @options.delete(name)

    def option?(name) = @options.include?(name)

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

    # The last command's exit status ($?), recorded after each command runs.
    def record_status(status) = @last_status = status

    # The positional parameters ($1..$n): `set`/`shift` replace them; a function
    # call brackets its body with #with_positional so the caller's are restored on
    # return — the $1..$n analogue of #without_loops.
    def replace_positional(values) = @positional = values

    def with_positional(values)
      saved = @positional
      @positional = values
      yield
    ensure
      @positional = saved
    end
  end
end
