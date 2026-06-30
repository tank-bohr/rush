# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    module Arithmetic
      # Splits an arithmetic expression into [kind, text] tokens (:num, :name,
      # :op), skipping blanks. Operators are listed longest-first so multi-byte
      # ones win over their prefixes; any other leftover character is an error.
      class Tokenizer
        extend T::Sig

        OPERATORS = [
          '<<=', '>>=',
          '<<', '>>', '<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=', '/=', '%=', '&=', '^=', '|=',
          '+', '-', '*', '/', '%', '<', '>', '&', '^', '|', '~', '!', '(', ')', '?', ':', '='
        ].freeze
        OPERATOR = Regexp.union(OPERATORS)
        NUMBER = /0[xX][0-9a-fA-F]+|\d+/
        NAME = /[A-Za-z_]\w*/
        TOKENS = { num: NUMBER, name: NAME, op: OPERATOR }.freeze

        sig { params(source: String).void }
        def initialize(source)
          @scanner = StringScanner.new(source)
        end

        sig { returns(T::Array[[Symbol, String]]) }
        def tokens
          result = []
          result << next_token while at_token?
          result
        end

        private

        sig { returns(T::Boolean) }
        def at_token?
          @scanner.skip(/\s+/)
          !@scanner.eos?
        end

        sig { returns([Symbol, String]) }
        def next_token
          # matched is non-nil right after a successful scan; .to_s satisfies the
          # [Symbol, String] token tuple.
          TOKENS.each { |kind, pattern| return [kind, @scanner.matched.to_s] if @scanner.scan(pattern) }

          raise ExpansionError, "arithmetic: unexpected #{@scanner.rest.inspect}"
        end
      end
    end
  end
end
