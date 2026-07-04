# typed: true
# frozen_string_literal: true

module Rush
  # Resolves shell parameters from the namespaces a shell exposes: ordinary
  # variables, special parameters ($?, $#, $$, $0, $@/$*, $-, $!), and positional
  # parameters ($1, $2, ...). Process-specific values, such as $$, are supplied
  # per call so the namespace stays part of ShellState while SystemCalls remains
  # outside it.
  class ShellParameters
    extend T::Sig

    sig do
      params(
        variables: ShellVariables,
        positional: Positional,
        name: String,
        status: T.proc.returns(Status)
      ).void
    end
    def initialize(variables:, positional:, name:, status:)
      @variables = variables
      @positional = positional
      @name = name
      @status = status
    end

    sig { params(parameter: String, pid: Integer).returns(T.nilable(String)) }
    def resolve(parameter, pid:)
      return pid.to_s if parameter == '$'

      special = special_parameters.fetch(parameter, nil)
      special ? special.call : ordinary_or_positional(parameter)
    end

    private

    sig { returns(T::Hash[String, T.proc.returns(T.nilable(String))]) }
    def special_parameters
      { '?' => -> { status }, '#' => -> { count }, '0' => -> { @name },
        '@' => -> { positional_all }, '*' => -> { positional_all }, '-' => -> { options },
        '!' => -> { background } }
    end

    sig { returns(String) }
    def status
      @status.call.exitstatus.to_s
    end

    sig { returns(String) }
    def count
      @positional.size.to_s
    end

    sig { returns(String) }
    def positional_all
      @positional.join(separator)
    end

    sig { returns(String) }
    def separator
      ifs = @variables.get('IFS')
      ifs ? (ifs.each_char.first || '') : ' '
    end

    sig { returns(String) }
    def options
      ''
    end

    sig { returns(NilClass) }
    def background
      nil
    end

    sig { params(parameter: String).returns(T.nilable(String)) }
    def ordinary_or_positional(parameter)
      return positional(parameter.to_i) if parameter.match?(/\A\d+\z/)

      @variables.get(parameter)
    end

    sig { params(index: Integer).returns(T.nilable(String)) }
    def positional(index)
      @positional[index - 1]
    end
  end
end
