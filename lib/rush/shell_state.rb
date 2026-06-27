# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: variables, the last
  # command's status, the shell name ($0) and the logical working directory.
  # The executor backfills pwd from the OS when the environment has no PWD.
  class ShellState
    attr_reader :environment
    attr_accessor :last_status, :name, :pwd

    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @last_status = Status.success
      @name = name
      @pwd = environment.get('PWD')
    end
  end
end
