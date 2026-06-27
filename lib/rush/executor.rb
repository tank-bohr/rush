# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port.
  class Executor
    attr_reader :system, :state, :builtins, :expander

    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      @expander = Expansion::Pipeline.new(self)
    end

    def run(node)
      @state.last_status = node.execute(self)
    end

    def run_simple(command) = CommandRunner.new(self, command).call
  end
end
