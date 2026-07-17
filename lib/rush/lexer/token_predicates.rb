# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Typed token-shape predicates for the raw [kind, value] tuples returned to
    # Racc. Keeping them here avoids repeating untyped tuple discriminator checks
    # in the lexer hot path.
    module TokenPredicates
      extend T::Sig

      private

      sig { params(token: Lexer::Token).returns(T::Boolean) }
      def word_token?(token)
        case token.first
        when :WORD then true
        else false
        end
      end
    end
  end
end
