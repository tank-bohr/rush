# frozen_string_literal: true

module Rush
  # Resolves a command name for `type` and `command -v`: a reserved word, a
  # function, a special or regular builtin, or an executable file found by
  # searching PATH (or used directly when the name contains a slash).
  class CommandLookup
    KEYWORDS = %w[! { } case do done elif else esac fi for if in then until while].freeze
    SPECIAL = %w[: . break continue eval exec exit export readonly return set shift times trap unset].freeze
    LABELS = { keyword: 'a shell keyword', function: 'a shell function',
               special: 'a special shell builtin', builtin: 'a shell builtin' }.freeze

    def initialize(executor)
      @executor = executor
    end

    # The `type`/`command -V` description line for a name, or nil if unknown.
    def describe(name)
      kind, detail = find(name)
      return nil unless kind
      return "#{name} is an alias for #{detail}" if kind == :alias

      "#{name} is #{kind == :file ? detail : LABELS.fetch(kind)}"
    end

    # [kind, detail] where kind is :alias/:keyword/:function/:special/:builtin/
    # :file (detail is the alias value or external path), or nil for an unknown
    # name. An alias outranks a function/builtin but not a reserved word.
    def find(name)
      kind = kind_of(name)
      return [kind, kind == :alias ? @executor.state.aliases.value(name) : name] if kind

      path = path_of(name)
      path && [:file, path]
    end

    private

    def kind_of(name)
      return :keyword if KEYWORDS.include?(name)
      return :alias if @executor.state.aliases.key?(name)
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
