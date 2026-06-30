# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `true` — does nothing, succeeds (status 0).
    class True < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        success
      end
    end
  end
end
