# typed: true
# frozen_string_literal: true

module Rush
  # Resolves a command name for `type` and `command -v`: a reserved word, a
  # function, a special or regular builtin, or an executable file found by
  # searching PATH (or used directly when the name contains a slash). #find runs
  # an ordered list of resolvers and returns the first Match (Unknown if none).
  class CommandLookup
    extend T::Sig

    KEYWORDS = %w[! { } case do done elif else esac fi for if in then until while].freeze
    SPECIAL = %w[: . break continue eval exec exit export readonly return set shift times trap unset].freeze
    RESOLVERS = %i[as_keyword as_alias as_function as_special as_builtin as_file].freeze

    # A resolved lookup result: it is "known", and subclasses render the line
    # `type` (#describe) and `command -v` (#terse) print. Only an executable
    # caches its own location; the others leave the cache untouched.
    class Match
      extend T::Sig

      # name is nilable: `command -v` with no operand resolves the nil name, which
      # flows through #find to Unknown.new(nil) (the Sorbet sig set tolerates this;
      # the RBS keeps the narrower String — the two checkers are independent).
      sig { params(name: T.nilable(String), detail: T.nilable(String)).void }
      def initialize(name, detail = nil)
        @name = name
        @detail = detail
      end

      sig { returns(T::Boolean) }
      def known?
        true
      end

      sig { params(_cache: T.untyped).void }
      def cache_into(_cache)
        nil
      end

      # describe/terse are the Match protocol #find's result is used through; the
      # subclasses provide them (the base is never instantiated, like AST::Node).
      sig { returns(T.nilable(String)) }
      def describe
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      def terse
        raise NotImplementedError
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :detail
    end

    # An unresolved name: not known, and nothing to describe.
    class Unknown < Match
      extend T::Sig

      sig { returns(T::Boolean) }
      def known?
        false
      end

      sig { returns(NilClass) }
      def describe
        nil
      end
    end

    # A keyword / function / special / regular builtin, named by a fixed label.
    class Labelled < Match
      extend T::Sig

      sig { returns(String) }
      def describe
        "#{name} is #{detail}"
      end

      sig { returns(String) }
      def terse
        T.must(name)
      end
    end

    # A shell alias; `command -v` prints its definition.
    class Aliased < Match
      extend T::Sig

      sig { returns(String) }
      def describe
        "#{name} is an alias for #{detail}"
      end

      sig { returns(String) }
      def terse
        "alias '#{"#{name}=#{detail}".gsub("'", %q('"'"'))}'"
      end
    end

    # An external executable found on PATH (or used directly via a slash path).
    class Executable < Match
      extend T::Sig

      sig { returns(String) }
      def describe
        "#{name} is #{detail}"
      end

      sig { returns(T.nilable(String)) }
      def terse
        detail
      end

      sig { params(cache: T.untyped).void }
      def cache_into(cache)
        cache[name] = detail
      end
    end

    sig { params(executor: T.untyped).void }
    def initialize(executor)
      @executor = executor
    end

    # The Match for a name (Unknown if it resolves to nothing). An alias outranks
    # a function/builtin but not a reserved word; a PATH/slash file is the last
    # resort.
    sig { params(name: T.nilable(String)).returns(Match) }
    def find(name)
      RESOLVERS.lazy.filter_map { |resolver| send(resolver, name) }.first || Unknown.new(name)
    end

    # The `type`/`command -V` description line for a name, or nil if unknown.
    sig { params(name: String).returns(T.nilable(String)) }
    def describe(name)
      find(name).describe
    end

    private

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_keyword(name)
      KEYWORDS.include?(name) && Labelled.new(name, 'a shell keyword')
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_alias(name)
      aliases.key?(name) && Aliased.new(name, aliases.value(name))
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_function(name)
      functions.key?(name) && Labelled.new(name, 'a shell function')
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_special(name)
      SPECIAL.include?(name) && Labelled.new(name, 'a special shell builtin')
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_builtin(name)
      @executor.builtins.key?(name) && Labelled.new(name, 'a shell builtin')
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def as_file(name)
      (path = path_of(name)) && Executable.new(name, path)
    end

    sig { returns(T.untyped) }
    def aliases
      @executor.state.aliases
    end

    sig { returns(T.untyped) }
    def functions
      @executor.state.functions
    end

    sig { params(name: T.nilable(String)).returns(T.untyped) }
    def path_of(name)
      return unless name
      return name if name.include?('/') && executable?(name)
      return if name.include?('/')

      dirs.map { |dir| join(dir, name) }.find { |candidate| executable?(candidate) }
    end

    sig { params(dir: String, name: String).returns(String) }
    def join(dir, name)
      dir.empty? ? name : "#{dir}/#{name}"
    end

    sig { params(path: String).returns(T.untyped) }
    def executable?(path)
      @executor.system.file?(path) && @executor.system.executable?(path)
    end

    sig { returns(T.untyped) }
    def dirs
      (@executor.state.environment.get('PATH') || '').split(':', -1)
    end
  end
end
