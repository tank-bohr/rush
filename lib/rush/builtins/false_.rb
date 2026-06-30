# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `false` — does nothing, fails (status 1).
    class False < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        failure
      end
    end
  end
end
