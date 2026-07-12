# typed: true
# frozen_string_literal: true

require 'forwardable'

module Rush
  # Semantic facade for shell variables: ordinary get/assign/export/readonly
  # operations plus dynamic local scopes and logical PWD tracking delegated to
  # Scope. Environment and Scope remain storage details behind this API.
  class ShellVariables
    extend T::Sig
    extend Forwardable

    def_delegators :@environment, :get, :export, :readonly, :unset, :exported, :update_lineno, :with_temporary,
                   :validate_assignment
    def_delegators :@scope, :pwd, :move_to, :seed_pwd, :current_pwd,
                   :begin_scope, :end_scope, :in_function?, :declare_local

    sig { params(environment: Environment).void }
    def initialize(environment)
      @environment = environment
      @scope = Scope.new(environment)
      @assignments = Assignments.new(self)
      @allexport = false
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
end
