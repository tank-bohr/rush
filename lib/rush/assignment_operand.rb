# typed: true
# frozen_string_literal: true

module Rush
  # Parsed `name[=value]` operands used by declaration builtins (`export`,
  # `readonly`, `local`). A missing `=` leaves value unset (nil); `name=` is a
  # present assignment to the empty string.
  class AssignmentOperand
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :value

    sig { params(name: String, value: T.nilable(String)).void }
    def initialize(name, value)
      @name = name
      @value = value
    end

    sig { params(text: String).returns(AssignmentOperand) }
    def self.parse(text)
      return new(text, nil) unless text.include?('=')

      parts = text.split('=', 2)
      new(parts.fetch(0), parts.fetch(1))
    end

    sig { params(environment: Environment).void }
    def assign_to(environment)
      assigned = value
      environment.assign(name, assigned) if assigned
    end
  end
end
