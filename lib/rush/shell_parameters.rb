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

    sig { params(state: T.untyped).void }
    def initialize(state)
      @state = state
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
      { '?' => -> { status }, '#' => -> { count }, '0' => -> { @state.name },
        '@' => -> { positional_all }, '*' => -> { positional_all }, '-' => -> { options },
        '!' => -> { background } }
    end

    sig { returns(String) }
    def status
      @state.last_status.exitstatus.to_s
    end

    sig { returns(String) }
    def count
      @state.positional.size.to_s
    end

    sig { returns(String) }
    def positional_all
      @state.positional.join(separator)
    end

    sig { returns(String) }
    def separator
      ifs = @state.variables.get('IFS')
      ifs ? (ifs.each_char.first || '') : ' '
    end

    sig { returns(String) }
    def options
      ''
    end

    sig { returns(T.nilable(String)) }
    def background
      @state.last_background_pid&.to_s
    end

    sig { params(parameter: String).returns(T.nilable(String)) }
    def ordinary_or_positional(parameter)
      return positional(parameter.to_i) if parameter.match?(/\A\d+\z/)

      @state.variables.get(parameter)
    end

    sig { params(index: Integer).returns(T.nilable(String)) }
    def positional(index)
      @state.positional[index - 1]
    end
  end
end
