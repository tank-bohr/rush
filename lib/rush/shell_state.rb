# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, the shell name ($0), the logical working directory, the
  # positional parameters and the function table. The executor backfills pwd from
  # the OS when the environment has no PWD.
  class ShellState
    attr_reader :environment, :functions
    attr_accessor :last_status, :name, :pwd, :positional

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @name = name
      @pwd = environment.get('PWD')
      initialize_runtime
    end

    # Shell options set by `set -o`-style flags (:nounset, :xtrace, ...).
    def set_option(name, enabled) = enabled ? @options.add(name) : @options.delete(name)

    def option?(name) = @options.include?(name)

    private

    def initialize_runtime
      @last_status = Status.success
      @positional = []
      @functions = FunctionTable.new
      @options = Set.new
    end
  end
end
