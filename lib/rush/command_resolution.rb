# typed: true
# frozen_string_literal: true

module Rush
  # Classifies a command for ordinary execution and carries the policies that
  # follow from that classification. This deliberately does not resolve aliases,
  # keywords or PATH: `type`/`command -v`, `command`, and execution have distinct
  # POSIX search modes and share only builtin metadata/vocabulary.
  class CommandResolution
    extend T::Sig

    # Ordinary execution's four mutually exclusive target kinds.
    class Kind < T::Enum
      enums do
        SPECIAL_BUILTIN = new('special_builtin')
        FUNCTION = new('function')
        BUILTIN = new('builtin')
        EXTERNAL = new('external')
      end
    end

    # How prefix assignments live for the selected target kind.
    class AssignmentLifetime < T::Enum
      enums do
        PERSISTENT = new('persistent')
        TEMPORARY = new('temporary')
        ENVIRONMENT = new('environment')
      end
    end

    # Whether redirect setup aborts the shell or fails only this command.
    class RedirectFailure < T::Enum
      enums do
        FATAL = new('fatal')
        ORDINARY = new('ordinary')
      end
    end

    Policy = T.type_alias { [AssignmentLifetime, RedirectFailure] }
    SPECIAL_BUILTINS = %w[: . break continue eval exec exit export readonly return set shift times trap unset].freeze
    POLICIES = T.let(
      {
        Kind::SPECIAL_BUILTIN => [AssignmentLifetime::PERSISTENT, RedirectFailure::FATAL].freeze,
        Kind::FUNCTION => [AssignmentLifetime::TEMPORARY, RedirectFailure::ORDINARY].freeze,
        Kind::BUILTIN => [AssignmentLifetime::TEMPORARY, RedirectFailure::ORDINARY].freeze,
        Kind::EXTERNAL => [AssignmentLifetime::ENVIRONMENT, RedirectFailure::ORDINARY].freeze
      }.freeze,
      T::Hash[Kind, Policy]
    )

    sig { returns(Kind) }
    attr_reader :kind

    sig { returns(AssignmentLifetime) }
    attr_reader :assignment_lifetime

    sig { returns(RedirectFailure) }
    attr_reader :redirect_failure

    sig { params(kind: Kind).void }
    def initialize(kind)
      @kind = kind
      @assignment_lifetime, @redirect_failure = POLICIES.fetch(kind)
    end
    private :initialize

    sig do
      params(name: String, functions: FunctionTable, builtins: Builtins::Registry).returns(CommandResolution)
    end
    def self.for_execution(name, functions, builtins)
      new(execution_kind(name, functions, builtins))
    end

    sig { params(name: String, builtins: Builtins::Registry).returns(T::Boolean) }
    def self.special_builtin?(name, builtins)
      SPECIAL_BUILTINS.include?(name) && builtins.key?(name)
    end

    sig { returns(T::Boolean) }
    def builtin?
      [Kind::SPECIAL_BUILTIN, Kind::BUILTIN].include?(kind)
    end

    sig { returns(T::Boolean) }
    def function?
      kind == Kind::FUNCTION
    end

    sig { returns(T::Boolean) }
    def persistent_assignments?
      assignment_lifetime == AssignmentLifetime::PERSISTENT
    end

    sig { returns(T::Boolean) }
    def temporary_assignments?
      assignment_lifetime == AssignmentLifetime::TEMPORARY
    end

    sig { returns(T::Boolean) }
    def fatal_redirect?
      redirect_failure == RedirectFailure::FATAL
    end

    sig do
      params(name: String, functions: FunctionTable, builtins: Builtins::Registry).returns(Kind)
    end
    private_class_method def self.execution_kind(name, functions, builtins)
      return Kind::SPECIAL_BUILTIN if special_builtin?(name, builtins)
      return Kind::FUNCTION if functions.key?(name)
      return Kind::BUILTIN if builtins.key?(name)

      Kind::EXTERNAL
    end
  end
end
