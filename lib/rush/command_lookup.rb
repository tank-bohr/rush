# frozen_string_literal: true

module Rush
  # Resolves a command name for `type` and `command -v`: a reserved word, a
  # function, a special or regular builtin, or an executable file found by
  # searching PATH (or used directly when the name contains a slash).
  class CommandLookup
    KEYWORDS = %w[! { } case do done elif else esac fi for if in then until while].freeze
    SPECIAL = %w[: . break continue eval exec exit export readonly return set shift times trap unset].freeze

    def initialize(executor)
      @executor = executor
    end

    # [kind, detail] where kind is :keyword/:function/:special/:builtin/:file,
    # or nil when the name resolves to nothing.
    def find(name)
      kind = kind_of(name)
      return [kind, name] if kind

      path = path_of(name)
      path && [:file, path]
    end

    private

    def kind_of(name)
      return :keyword if KEYWORDS.include?(name)
      return :function if @executor.state.functions.key?(name)
      return :special if SPECIAL.include?(name)

      :builtin if @executor.builtins.key?(name)
    end

    def path_of(name)
      return name if name.include?('/') && executable?(name)
      return nil if name.include?('/')

      dirs.map { |dir| join(dir, name) }.find { |candidate| executable?(candidate) }
    end

    def join(dir, name) = dir.empty? ? name : "#{dir}/#{name}"

    def executable?(path) = @executor.system.file?(path) && @executor.system.executable?(path)

    def dirs = (@executor.state.environment.get('PATH') || '').split(':', -1)
  end
end
