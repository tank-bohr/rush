# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: the variable environment,
  # the last command's status ($?, the one field with behaviour here), the shell
  # name ($0), and the session sub-objects it bundles for the rest of the
  # interpreter to drive directly — the variable Scope (local scoping + cwd),
  # LoopNesting, Options, Positional, the function/alias/trap tables and the
  # command-location cache.
  class ShellState
    attr_reader :environment, :functions, :traps, :aliases, :command_hash, :name, :scope, :loops,
                :options, :last_status, :positional

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @name = name
      @scope = Scope.new(environment)
      @traps = TrapTable.new
      @last_status = Status.success
      @loops = LoopNesting.new
      @options = Options.new
      @positional = Positional.new
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end

    # The last command's exit status ($?), recorded after each command runs.
    def record_status(status)
      @last_status = status
    end
  end
end
