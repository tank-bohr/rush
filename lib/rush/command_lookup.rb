# frozen_string_literal: true

module Rush
  # Resolves a command name for `type` and `command -v`: a reserved word, a
  # function, a special or regular builtin, or an executable file found by
  # searching PATH (or used directly when the name contains a slash). #find runs
  # an ordered list of resolvers and returns the first Match (Unknown if none).
  class CommandLookup
    KEYWORDS = %w[! { } case do done elif else esac fi for if in then until while].freeze
    SPECIAL = %w[: . break continue eval exec exit export readonly return set shift times trap unset].freeze
    RESOLVERS = %i[as_keyword as_alias as_function as_special as_builtin as_file].freeze

    # A resolved lookup result: it is "known", and subclasses render the line
    # `type` (#describe) and `command -v` (#terse) print. Only an executable
    # caches its own location; the others leave the cache untouched.
    class Match
      def initialize(name, detail = nil)
        @name = name
        @detail = detail
      end

      def known? = true
      def cache_into(_cache) = nil

      private

      attr_reader :name, :detail
    end

    # An unresolved name: not known, and nothing to describe.
    class Unknown < Match
      def known? = false
      def describe = nil
    end

    # A keyword / function / special / regular builtin, named by a fixed label.
    class Labelled < Match
      def describe = "#{name} is #{detail}"
      def terse = name
    end

    # A shell alias; `command -v` prints its definition.
    class Aliased < Match
      def describe = "#{name} is an alias for #{detail}"
      def terse = "alias '#{"#{name}=#{detail}".gsub("'", %q('"'"'))}'"
    end

    # An external executable found on PATH (or used directly via a slash path).
    class Executable < Match
      def describe = "#{name} is #{detail}"
      def terse = detail
      def cache_into(cache) = cache[name] = detail
    end

    def initialize(executor)
      @executor = executor
    end

    # The Match for a name (Unknown if it resolves to nothing). An alias outranks
    # a function/builtin but not a reserved word; a PATH/slash file is the last
    # resort.
    def find(name) = RESOLVERS.lazy.filter_map { |resolver| send(resolver, name) }.first || Unknown.new(name)

    # The `type`/`command -V` description line for a name, or nil if unknown.
    def describe(name) = find(name).describe

    private

    def as_keyword(name) = KEYWORDS.include?(name) && Labelled.new(name, 'a shell keyword')
    def as_alias(name) = aliases.key?(name) && Aliased.new(name, aliases.value(name))
    def as_function(name) = functions.key?(name) && Labelled.new(name, 'a shell function')
    def as_special(name) = SPECIAL.include?(name) && Labelled.new(name, 'a special shell builtin')
    def as_builtin(name) = @executor.builtins.key?(name) && Labelled.new(name, 'a shell builtin')
    def as_file(name) = (path = path_of(name)) && Executable.new(name, path)

    def aliases = @executor.state.aliases
    def functions = @executor.state.functions

    def path_of(name)
      return unless name
      return name if name.include?('/') && executable?(name)
      return if name.include?('/')

      dirs.map { |dir| join(dir, name) }.find { |candidate| executable?(candidate) }
    end

    def join(dir, name) = dir.empty? ? name : "#{dir}/#{name}"

    def executable?(path) = @executor.system.file?(path) && @executor.system.executable?(path)

    def dirs = (@executor.state.environment.get('PATH') || '').split(':', -1)
  end
end
