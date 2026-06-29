# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `cd [dir]` — change the working directory, maintaining a *logical* PWD
    # (not Dir.pwd, which resolves symlinks) plus OLDPWD. Defaults to $HOME.
    class Cd < Base
      def call
        target = operands.first || executor.state.environment.get('HOME')
        target ? change_to(target) : report('HOME not set')
      end

      private

      def change_to(dir)
        executor.system.chdir(dir)
        update_pwd(dir)
        success
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      def update_pwd(dir)
        state = executor.state
        # scope.pwd is non-nil here (seeded at startup); .to_s satisfies the
        # String base of expand_path without changing behaviour on that path.
        state.scope.move_to(executor.system.expand_path(dir, state.scope.pwd.to_s))
      end

      def report(message)
        stderr.puts("rush: cd: #{message}")
        failure
      end
    end
  end
end
