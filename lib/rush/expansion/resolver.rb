# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Resolves a parameter name to its current value (or nil when unset): the
    # special parameters, the positional parameters ($1, $2, ...), and ordinary
    # shell variables. $- (options) and $! (last background pid) are placeholders
    # until set-options and job control land.
    class Resolver
      extend T::Sig

      SPECIAL = {
        '?' => :status, '#' => :count, '$' => :pid, '0' => :shell_name,
        '@' => :positional_all, '*' => :positional_all, '-' => :options, '!' => :background
      }.freeze

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def resolve(name)
        return send(SPECIAL.fetch(name)) if SPECIAL.key?(name)
        return positional(name.to_i) if name.match?(/\A\d+\z/)

        state.environment.get(name)
      end

      private

      sig { returns(ShellState) }
      def state
        @executor.state
      end

      sig { returns(String) }
      def status
        state.last_status.exitstatus.to_s
      end

      sig { returns(String) }
      def count
        state.positional.size.to_s
      end

      sig { returns(String) }
      def pid
        @executor.system.pid.to_s
      end

      sig { returns(String) }
      def shell_name
        state.name
      end

      sig { returns(String) }
      def positional_all
        state.positional.join(separator)
      end

      sig { returns(String) }
      def separator
        ifs = state.environment.get('IFS')
        ifs ? ifs[0].to_s : ' '
      end

      sig { returns(String) }
      def options
        ''
      end

      sig { returns(NilClass) }
      def background
        nil
      end

      sig { params(index: Integer).returns(T.nilable(String)) }
      def positional(index)
        state.positional[index - 1]
      end
    end
  end
end
