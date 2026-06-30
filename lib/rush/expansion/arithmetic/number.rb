# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # Pure 64-bit integer arithmetic for $(( )): two's-complement wrapping (so
      # overflow matches dash), C-style truncated-toward-zero division/modulo,
      # and the unary/binary operator tables the evaluator dispatches through.
      # Comparison and logical results are 1 or 0. Never uses Kernel#eval.
      module Number
        extend T::Sig

        module_function

        LIMIT = 1 << 63

        # Parse an integer constant (decimal, 0-octal or 0x-hex, optional sign and
        # surrounding blanks), as both literals and variable values are read. The
        # raising Integer() (not the exception:false form) lets the failure path
        # translate to an ExpansionError; it also types cleanly under both checkers
        # (Sorbet's RBI mistypes Integer(exception: false) as non-nil). Kernel.* so
        # the bare Kernel calls resolve in this module_function module under Sorbet.
        sig { params(text: String).returns(Integer) }
        def parse(text)
          Kernel.Integer(text)
        rescue ArgumentError
          Kernel.raise(ExpansionError, "arithmetic: invalid number #{text.inspect}")
        end

        # op is String, not the literal set ("+"|"-"|"!"|"~"): it is a token the
        # parser validates at runtime (UNARY.include? then UNARY.fetch), never
        # statically narrowed — `advance` returns String — so neither checker can
        # reach the union without an unchecked cast. RBS *can* spell string-literal
        # unions (Sorbet cannot), but here there is no narrowing point to feed one.
        sig { params(op: String, value: Integer).returns(Integer) }
        def unary(op, value)
          wrap(UNARY.fetch(op).call(value))
        end

        sig { params(op: String, left: Integer, right: Integer).returns(Integer) }
        def binary(op, left, right)
          wrap(BINARY.fetch(op).call(left, right))
        end

        sig { params(num: Integer).returns(Integer) }
        def wrap(num)
          ((num + LIMIT) % (LIMIT << 1)) - LIMIT
        end

        sig { params(flag: T::Boolean).returns(Integer) }
        def bool(flag)
          flag ? 1 : 0
        end

        sig { params(left: Integer, right: Integer).returns(Integer) }
        def divide(left, right)
          Kernel.raise(ExpansionError, 'arithmetic: division by zero') if right.zero?

          magnitude = left.abs / right.abs
          left.negative? == right.negative? ? magnitude : -magnitude
        end

        sig { params(left: Integer, right: Integer).returns(Integer) }
        def modulo(left, right)
          left - (divide(left, right) * right)
        end

        # The #: types each lambda's parameters: Steep does not propagate a frozen
        # hash's declared value type into bare `->()` literals, so without it the
        # params stay untyped (and every operator body with them). See number.rbs.
        UNARY = {
          '+' => ->(value) { value }, #: ^(Integer) -> Integer
          '-' => ->(value) { -value }, #: ^(Integer) -> Integer
          '!' => ->(value) { bool(value.zero?) }, #: ^(Integer) -> Integer
          '~' => ->(value) { ~value } #: ^(Integer) -> Integer
        }.freeze

        BINARY = {
          '+' => ->(left, right) { left + right }, #: ^(Integer, Integer) -> Integer
          '-' => ->(left, right) { left - right }, #: ^(Integer, Integer) -> Integer
          '*' => ->(left, right) { left * right }, #: ^(Integer, Integer) -> Integer
          '/' => ->(left, right) { divide(left, right) }, #: ^(Integer, Integer) -> Integer
          '%' => ->(left, right) { modulo(left, right) }, #: ^(Integer, Integer) -> Integer
          # Shift counts are masked to 6 bits, matching x86-64 (and so dash) for
          # the out-of-range/negative counts that C leaves undefined.
          '<<' => ->(left, right) { left << (right & 63) }, #: ^(Integer, Integer) -> Integer
          '>>' => ->(left, right) { left >> (right & 63) }, #: ^(Integer, Integer) -> Integer
          '&' => ->(left, right) { left & right }, #: ^(Integer, Integer) -> Integer
          '|' => ->(left, right) { left | right }, #: ^(Integer, Integer) -> Integer
          '^' => ->(left, right) { left ^ right }, #: ^(Integer, Integer) -> Integer
          '<' => ->(left, right) { bool(left < right) }, #: ^(Integer, Integer) -> Integer
          '<=' => ->(left, right) { bool(left <= right) }, #: ^(Integer, Integer) -> Integer
          '>' => ->(left, right) { bool(left > right) }, #: ^(Integer, Integer) -> Integer
          '>=' => ->(left, right) { bool(left >= right) }, #: ^(Integer, Integer) -> Integer
          '==' => ->(left, right) { bool(left == right) }, #: ^(Integer, Integer) -> Integer
          '!=' => ->(left, right) { bool(left != right) } #: ^(Integer, Integer) -> Integer
        }.freeze
      end
    end
  end
end
