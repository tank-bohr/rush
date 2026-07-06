# typed: true
# frozen_string_literal: true

module Rush
  # The program text and shell parameters implied by
  # `-c command_string [command_name [argument...]]`.
  class CommandInput
    extend T::Sig

    sig { params(operands: T::Array[String]).void }
    def initialize(operands)
      @operands = operands
    end

    sig { returns(String) }
    def name
      @operands.fetch(1, 'rush')
    end

    sig { returns(T::Array[String]) }
    def positionals
      @operands.drop(2)
    end

    sig { returns(String) }
    def source
      @operands.fetch(0) { raise InvocationError, '-c requires an argument' }
    end
  end

  # The program text and shell parameters implied by a script-file operand:
  # the path becomes $0, later operands the positional parameters, and the
  # file is read lazily — unreadable files are an invocation error (status 2,
  # like dash).
  class ScriptInput
    extend T::Sig

    sig { params(operands: T::Array[String], system: SystemCalls).void }
    def initialize(operands, system)
      @operands = operands
      @system = system
    end

    sig { returns(String) }
    def name
      @operands.fetch(0)
    end

    sig { returns(T::Array[String]) }
    def positionals
      @operands.drop(1)
    end

    sig { returns(String) }
    def source
      @system.read_file(name)
    rescue SystemCallError => e
      raise InvocationError, "cannot open #{name}: #{e.message}"
    end
  end

  # The program text and shell parameters implied by reading stdin (implicitly
  # or via -s): the operands become the positional parameters and $0 stays the
  # shell name.
  class StdinInput
    extend T::Sig

    sig { params(operands: T::Array[String], system: SystemCalls).void }
    def initialize(operands, system)
      @operands = operands
      @system = system
    end

    sig { returns(String) }
    def name
      'rush'
    end

    sig { returns(T::Array[String]) }
    def positionals
      @operands
    end

    sig { returns(String) }
    def source
      @system.stdin.read
    end
  end
end
