# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, and the shell name ($0). Grows with options/traps/etc.
  class ShellState
    attr_reader :environment
    attr_accessor :last_status, :name

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @last_status = Status.success
      @name = name
    end
  end
end
