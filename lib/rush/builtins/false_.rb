# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `false` — does nothing, fails (status 1).
    class False < Base
      def call
        failure
      end
    end
  end
end
