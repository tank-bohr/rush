# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `pwd` — print the shell's logical working directory.
    class Pwd < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        stdout.puts(executor.state.variables.pwd)
        success
      end
    end
  end
end
