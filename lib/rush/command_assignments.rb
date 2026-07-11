# typed: true
# frozen_string_literal: true

module Rush
  # Applies assignment words attached to a simple command. Bare assignments
  # persist in shell variables; assignments before an external command overlay
  # the exported environment without mutating the shell.
  class CommandAssignments
    extend T::Sig

    sig { params(assignments: T::Array[AST::Assignment], expander: Expansion::Pipeline).void }
    def initialize(assignments, expander)
      @assignments = assignments
      @expander = expander
    end

    sig { returns(T::Array[String]) }
    def names
      @assignments.map(&:name)
    end

    sig { params(variables: ShellVariables).void }
    def persist_to(variables)
      @assignments.each { |assignment| variables.assign(assignment.name, expand(assignment)) }
    end

    sig { params(variables: ShellVariables).returns(T::Hash[String, String]) }
    def environment_for(variables)
      @assignments.each_with_object(variables.exported) do |assignment, env|
        env[assignment.name] = expand(assignment)
      end
    end

    private

    sig { params(assignment: AST::Assignment).returns(String) }
    def expand(assignment)
      @expander.expand_value(assignment.value, tilde: :assignment)
    end
  end
end
