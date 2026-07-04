# typed: true
# frozen_string_literal: true

module Rush
  # Parsed `name[=value]` operands used by declaration builtins (`export`,
  # `readonly`, `local`). A missing `=` leaves value unset (nil); `name=` is a
  # present assignment to the empty string. The parsed name is needed before
  # assignment for `local`, which must snapshot the old value first.
  class AssignmentOperand
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :value

    sig { params(text: String).void }
    def initialize(text)
      @name = text
      @value = nil
      parse(text) if text.include?('=')
    end

    private

    sig { params(text: String).void }
    def parse(text)
      parts = text.split('=', 2)
      @name = parts.fetch(0)
      @value = parts.fetch(1)
    end
  end
end
