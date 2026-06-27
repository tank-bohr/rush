# frozen_string_literal: true

module Rush
  module Expansion
    # Resolves a parameter name to its current value (or nil when unset): the
    # special parameters, the positional parameters ($1, $2, ...), and ordinary
    # shell variables. $- (options) and $! (last background pid) are placeholders
    # until set-options and job control land.
    class Resolver
      SPECIAL = {
        '?' => :status, '#' => :count, '$' => :pid, '0' => :shell_name,
        '@' => :positional_all, '*' => :positional_all, '-' => :options, '!' => :background
      }.freeze

      def initialize(executor)
        @executor = executor
      end

      def resolve(name)
        return send(SPECIAL[name]) if SPECIAL.key?(name)
        return positional(name.to_i) if name.match?(/\A\d+\z/)

        state.environment.get(name)
      end

      private

      def state = @executor.state

      def status = state.last_status.exitstatus.to_s

      def count = state.positional.size.to_s

      def pid = @executor.system.pid.to_s

      def shell_name = state.name

      def positional_all = state.positional.join(' ')

      def options = ''

      def background = nil

      def positional(index) = state.positional[index - 1]
    end
  end
end
