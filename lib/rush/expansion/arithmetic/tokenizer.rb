# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    module Arithmetic
      # Splits an arithmetic expression into [kind, text] tokens (:num, :name,
      # :op), skipping blanks. Operators are listed longest-first so multi-byte
      # ones win over their prefixes; any other leftover character is an error.
      class Tokenizer
        OPERATORS = [
          '<<=', '>>=',
          '<<', '>>', '<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=', '/=', '%=', '&=', '^=', '|=',
          '+', '-', '*', '/', '%', '<', '>', '&', '^', '|', '~', '!', '(', ')', '?', ':', '='
        ].freeze
        OPERATOR = Regexp.union(OPERATORS)
        NUMBER = /0[xX][0-9a-fA-F]+|\d+/
        NAME = /[A-Za-z_]\w*/

        def initialize(source)
          @scanner = StringScanner.new(source)
        end

        def tokens
          result = []
          result << next_token while at_token?
          result
        end

        private

        def at_token?
          @scanner.skip(/\s+/)
          !@scanner.eos?
        end

        def next_token
          return [:num, @scanner.matched] if @scanner.scan(NUMBER)
          return [:name, @scanner.matched] if @scanner.scan(NAME)
          return [:op, @scanner.matched] if @scanner.scan(OPERATOR)

          raise ExpansionError, "arithmetic: unexpected #{@scanner.rest.inspect}"
        end
      end
    end
  end
end
