# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `cd [dir]` — change the working directory, maintaining a *logical* PWD
    # (not Dir.pwd, which resolves symlinks) plus OLDPWD. Defaults to $HOME.
    class Cd < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        target = operands.first || executor.state.variables.get('HOME')
        target ? change_to(target) : report('HOME not set')
      end

      private

      sig { params(dir: T.untyped).returns(T.untyped) }
      def change_to(dir)
        executor.system.chdir(dir)
        update_pwd(dir)
        success
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      sig { params(dir: T.untyped).returns(T.untyped) }
      def update_pwd(dir)
        variables = executor.state.variables
        variables.move_to(executor.system.expand_path(dir, variables.current_pwd))
      end

      sig { params(message: T.untyped).returns(T.untyped) }
      def report(message)
        stderr.puts("rush: cd: #{message}")
        failure
      end
    end
  end
end
