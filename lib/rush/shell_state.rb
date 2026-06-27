# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, the shell name ($0), the logical working directory, the
  # positional parameters and the function table. The executor backfills pwd from
  # the OS when the environment has no PWD.
  class ShellState
    attr_reader :environment, :functions, :traps, :aliases
    attr_accessor :last_status, :name, :pwd, :positional

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

    private

    def restore(name, value)
      value.nil? ? @environment.unset(name) : @environment.assign(name, value)
    end

    def initialize_runtime
      @last_status = Status.success
      @positional = []
      @options = Set.new
      @scopes = []
      build_tables
    end

    def build_tables
      @functions = FunctionTable.new
      @aliases = AliasTable.new
    end
  end
end
