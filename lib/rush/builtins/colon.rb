# frozen_string_literal: true

module Rush
  module Builtins
    # `:` — the null command; expands its arguments and always succeeds.
    class Colon < Base
      def call
        success
      end
    end
  end
end
