# typed: true
# frozen_string_literal: true

module Rush
  # Applies `name[=value]` declaration operands to shell variables. A missing `=`
  # leaves the variable unchanged; `name=` assigns the empty string. Callers may
  # pass a block to run after parsing the name but before assignment, which lets
  # `local` snapshot the old value first.
  class Assignments
    extend T::Sig

    sig { params(variables: ShellVariables).void }
    def initialize(variables)
      @variables = variables
    end

    sig { params(text: String).returns(String) }
    def apply(text)
      name, value = parse(text)
      assign(name, value)
      name
    end

    sig { params(text: String).returns(String) }
    def apply_local(text)
      name, value = parse(text)
      @variables.declare_local(name)
      assign(name, value)
      name
    end

    private

    sig { params(text: String).returns([String, T.nilable(String)]) }
    def parse(text)
      return [text, nil] unless text.include?('=')

      parts = text.split('=', 2)
      [parts.fetch(0), parts.fetch(1)]
    end

    sig { params(name: String, value: T.nilable(String)).void }
    def assign(name, value)
      @variables.assign(name, value) if value
    end
  end
end
