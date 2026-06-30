# typed: true
# frozen_string_literal: true

module Rush
  module Redirection
    # Binds a here-document's (already-expanded) body to the redirection's fd —
    # fd 0 by default — as a readable stream supplied by the SystemCalls port.
    class HereDocRedirect
      extend T::Sig

      sig { params(redirect: T.untyped, body: T.untyped, io: T.untyped, system: T.untyped).returns(T.untyped) }
      def apply(redirect, body, io, system)
        io.with(redirect.io_number || 0, system.here_doc(body))
      end
    end
  end
end
