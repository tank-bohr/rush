# typed: true
# frozen_string_literal: true

module Rush
  # A parsed `name[=value]` operand bound to the environment it may assign. A
  # missing `=` leaves value unset (nil); `name=` is a present assignment to the
  # empty string. `local` can snapshot #name before calling #assign.
  class AssignmentOperand
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { params(text: String, environment: Environment).void }
    def initialize(text, environment)
      @environment = environment
      @name = text
      @value = nil
      parse(text) if text.include?('=')
    end

    sig { void }
    def assign
      assigned = @value
      @environment.assign(name, assigned) if assigned
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
