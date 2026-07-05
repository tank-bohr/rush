# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `cd [dir]` — change the working directory, maintaining a *logical* PWD
    # (not Dir.pwd, which resolves symlinks) plus OLDPWD. Defaults to $HOME.
    class Cd < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        target = operands.first || executor.state.variables.get('HOME')
        return report('HOME not set') unless target

        target == '-' ? change_back : change_to(target)
      end

      private

      sig { params(dir: String).returns(Status) }
      def change_to(dir)
        perform_chdir(dir)
        success
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      sig { returns(Status) }
      def change_back
        dir = oldpwd
        perform_chdir(dir)
        success_with_echo
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      sig { returns(String) }
      def oldpwd
        executor.state.variables.get('OLDPWD') || executor.state.variables.current_pwd
      end

      sig { params(dir: String).void }
      def perform_chdir(dir)
        executor.system.chdir(dir)
        update_pwd(dir)
      end

      sig { returns(Status) }
      def success_with_echo
        stdout.puts(executor.state.variables.current_pwd)
        success
      end

      sig { params(dir: String).void }
      def update_pwd(dir)
        variables = executor.state.variables
        variables.move_to(executor.system.expand_path(dir, variables.current_pwd))
      end

      sig { params(message: String).returns(Status) }
      def report(message)
        stderr.puts("rush: cd: #{message}")
        failure
      end
    end
  end
end
