# frozen_string_literal: true

module Rush
  module Builtins
    # `pwd` — print the shell's logical working directory.
    class Pwd < Base
      def call
        stdout.puts(executor.state.pwd)
        success
      end
    end
  end
end
