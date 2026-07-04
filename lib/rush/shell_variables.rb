# typed: true
# frozen_string_literal: true

module Rush
  # Semantic facade for shell variables: ordinary get/assign/export/readonly
  # operations plus the dynamic local scopes and logical PWD tracking inherited
  # from Scope. Environment remains the storage detail behind this API.
  class ShellVariables < Scope
    extend T::Sig

    sig { params(name: String).returns(T.nilable(String)) }
    def get(name)
      environment.get(name)
    end

    sig { params(name: String, value: String).returns(String) }
    def assign(name, value)
      environment.assign(name, value)
    end

    sig { params(name: String).void }
    def export(name)
      environment.export(name)
    end

    sig { params(name: String).void }
    def readonly(name)
      environment.readonly(name)
    end

    sig { params(name: String).void }
    def unset(name)
      environment.unset(name)
    end

    sig { returns(T::Hash[String, String]) }
    def exported
      environment.exported
    end

    sig { params(text: String).void }
    def export_operand(text)
      export(Assignments.new(self).apply(text))
    end

    sig { params(text: String).void }
    def readonly_operand(text)
      readonly(Assignments.new(self).apply(text))
    end

    sig { params(text: String).void }
    def declare_local_operand(text)
      Assignments.new(self).apply(text) { |name| declare_local(name) }
    end
  end
end
