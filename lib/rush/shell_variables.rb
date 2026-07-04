# typed: true
# frozen_string_literal: true

module Rush
  # Semantic facade for shell variables: ordinary get/assign/export/readonly
  # operations plus dynamic local scopes and logical PWD tracking delegated to
  # Scope. Environment and Scope remain storage details behind this API.
  class ShellVariables
    extend T::Sig

    sig { returns(T.nilable(String)) }
    def pwd
      @scope.pwd
    end

    sig { params(environment: Environment).void }
    def initialize(environment)
      @environment = environment
      @scope = Scope.new(environment)
      @assignments = Assignments.new(self)
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def get(name)
      @environment.get(name)
    end

    sig { params(name: String, value: String).returns(String) }
    def assign(name, value)
      @environment.assign(name, value)
    end

    sig { params(name: String).void }
    def export(name)
      @environment.export(name)
    end

    sig { params(name: String).void }
    def readonly(name)
      @environment.readonly(name)
    end

    sig { params(name: String).void }
    def unset(name)
      @environment.unset(name)
    end

    sig { returns(T::Hash[String, String]) }
    def exported
      @environment.exported
    end

    sig { params(pwd: String).void }
    def move_to(pwd)
      @scope.move_to(pwd)
    end

    sig { params(path: String).void }
    def seed_pwd(path)
      @scope.seed_pwd(path)
    end

    sig { returns(String) }
    def current_pwd
      @scope.current_pwd
    end

    sig { void }
    def begin_scope
      @scope.begin_scope
    end

    sig { void }
    def end_scope
      @scope.end_scope
    end

    sig { returns(T::Boolean) }
    def in_function?
      @scope.in_function?
    end

    sig { params(name: String).void }
    def declare_local(name)
      @scope.declare_local(name)
    end

    sig { params(text: String).void }
    def export_operand(text)
      export(@assignments.apply(text))
    end

    sig { params(text: String).void }
    def readonly_operand(text)
      readonly(@assignments.apply(text))
    end

    sig { params(text: String).void }
    def declare_local_operand(text)
      @assignments.apply_local(text)
    end
  end
end
