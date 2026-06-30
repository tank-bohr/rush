# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `hash [-r] [name ...]` — the command-location cache. With names, look each up
    # in PATH and remember it; a name containing a slash or naming a builtin /
    # function / keyword is a silent no-op, an unresolvable name an error (status
    # 1). `-r` forgets all. With no operands, list the remembered locations, one
    # path per line, sorted by name.
    #
    # Divergence: rush does not auto-populate the cache as commands run (POSIX/dash
    # remember a utility's location when it is used); only an explicit `hash name`
    # records one. Observable only via `<cmd>; hash` and noted in the journal — the
    # cache is otherwise bit-for-bit consistent with dash.
    class Hash < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        return reset if operands.first == '-r'
        return list if operands.empty?

        remember(operands)
      end

      private

      sig { returns(T.untyped) }
      def cache
        executor.state.command_hash
      end

      sig { returns(T.untyped) }
      def reset
        cache.clear
        success
      end

      sig { returns(T.untyped) }
      def list
        cache.sort.each { |_name, path| stdout.puts(path) }
        success
      end

      sig { params(names: T.untyped).returns(T.untyped) }
      def remember(names)
        missing = names.reject { |name| known?(name) }
        missing.each { |name| stderr.puts("rush: hash: #{name}: not found") }
        missing.empty? ? success : failure
      end

      # Whether the name is a known command; a resolvable PATH command is also
      # cached (a slash path or a builtin / function is known but not cached).
      sig { params(name: T.untyped).returns(T.untyped) }
      def known?(name)
        return true if name.include?('/')

        match = CommandLookup.new(executor).find(name)
        match.cache_into(cache)
        match.known?
      end
    end
  end
end
