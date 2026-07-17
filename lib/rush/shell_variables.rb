# typed: true
# frozen_string_literal: true

module Rush
  # Semantic facade for shell variables: ordinary get/assign/export/readonly
  # operations plus dynamic local scopes and logical PWD tracking delegated to
  # Scope. Environment and Scope remain storage details behind this API.
  # Exact forwarding methods replace Forwardable's untyped splat surface; the
  # cohesive facade sits five lines above the generic class-length threshold.
  # rubocop:disable Metrics/ClassLength
  class ShellVariables
    extend T::Sig

    sig { params(environment: Environment).void }
    def initialize(environment)
      @environment = T.let(environment, Environment)
      @scope = T.let(Scope.new(environment), Scope)
      @assignments = T.let(Assignments.new(self), Assignments)
      @allexport = T.let(false, T::Boolean)
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def get(name)
      @environment.get(name)
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

    sig { params(line: Integer).returns(T.nilable(String)) }
    def update_lineno(line)
      @environment.update_lineno(line)
    end

    sig do
      type_parameters(:U)
        .params(values: T::Hash[String, String], blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_temporary(values, &blk)
      @environment.with_temporary(values, &blk)
    end

    sig { params(name: String).void }
    def validate_assignment(name)
      @environment.validate_assignment(name)
    end

    sig { returns(T.nilable(String)) }
    def pwd
      @scope.pwd
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

    sig { params(enabled: T::Boolean).void }
    def allexport=(enabled)
      @allexport = enabled == true
    end

    sig { returns(T::Array[String]) }
    def locale_settings
      %w[LC_COLLATE LC_CTYPE].map { |category| locale(category) }
    end

    # The locale name for one category: a non-empty LC_ALL overrides the
    # category-specific variable, then LANG, with the POSIX locale as default.
    sig { params(category: String).returns(String) }
    def locale(category)
      names = ['LC_ALL', category, 'LANG']
      names.filter_map { |name| get(name) }.reject(&:empty?).first || 'C'
    end

    sig { params(name: String, value: String).returns(String) }
    def assign(name, value)
      @environment.assign(name, value)
      export(name) if @allexport
      value
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
  # rubocop:enable Metrics/ClassLength
end
