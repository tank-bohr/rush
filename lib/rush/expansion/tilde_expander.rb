# frozen_string_literal: true

module Rush
  module Expansion
    # Tilde expansion (step 1): a leading unquoted `~` or `~name` in a word's
    # first literal segment becomes $HOME or the named user's home directory. It
    # is left untouched when there is no such user, or when HOME is unset for a
    # bare `~`. In assignment context it also expands after each unquoted colon
    # (so PATH=~/bin:~root/x works).
    class TildeExpander
      def initialize(executor)
        @executor = executor
      end

      def expand(segments, assignment:)
        head = segments.first
        return segments if head.nil? || head.kind != :literal || head.quoted

        [head.with(value: rewrite(head.value, assignment))] + segments[1..]
      end

      private

      def rewrite(text, assignment)
        return prefix(text) unless assignment

        text.split(':', -1).map { |piece| prefix(piece) }.join(':')
      end

      def prefix(text)
        return text unless text.start_with?('~')

        name, rest = split(text[1..])
        home = resolve(name)
        home ? home + rest : text
      end

      def split(body)
        slash = body.index('/')
        slash ? [body[0...slash], body[slash..]] : [body, '']
      end

      def resolve(name)
        return @executor.state.environment.get('HOME') if name.empty?

        @executor.system.home_dir(name)
      end
    end
  end
end
