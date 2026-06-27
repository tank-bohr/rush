# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it.
  class Executor
    attr_reader :system, :state, :builtins, :redirections, :expander, :io

    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      setup
    end

    def run(node) = @state.last_status = node.execute(self)

    def run_simple(command) = CommandRunner.new(self, command).call

    private

    def setup
      @redirections = Redirection.default_registry
      @expander = Expansion::Pipeline.new(self)
      @io = IoTable.standard(@system)
      @state.pwd ||= @system.pwd
    end
  end
end
