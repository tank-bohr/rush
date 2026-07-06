# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # A redirection: a kind (:in/:out/:append/:dup_in/:dup_out/:readwrite/
    # :clobber), an unexpanded target Word, and an optional explicit fd parsed
    # from a leading IO_NUMBER (nil means the kind's default fd).
    Redirect = Data.define(:kind, :target, :io_number)

    # Behaviour for the Data-defined redirection payload.
    class Redirect
      extend T::Sig

      sig { returns(Integer) }
      def source_line
        target.source_line
      end
    end
  end
end
