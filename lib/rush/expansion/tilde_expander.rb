# frozen_string_literal: true

module Rush
  module Expansion
    # Tilde expansion (step 1): a leading unquoted `~` or `~name` in a word's
    # first literal segment becomes $HOME or the named user's home directory. It
    # is left untouched when there is no such user, or when HOME is unset for a
    # bare `~`. This base handles the leading form; AssignmentTilde extends it to
    # also expand after each unquoted colon, and NoTilde disables it entirely.
    class TildeExpander
      def initialize(executor, segments)
        @executor = executor
        @segments = segments
      end

      def expand
        head = @segments.first
        return @segments unless expandable?(head)

        [head.with(value: rewrite(head.value))] + @segments[1..]
      end

      private

      def expandable?(head) = head&.kind == :literal && !head.quoted

      def rewrite(text) = prefix(text)

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

    # Assignment context (PATH=~/bin:~root/x): the leading tilde plus one after
    # each unquoted colon, so every colon-separated piece gets the ~ treatment.
    class AssignmentTilde < TildeExpander
      private

      def rewrite(text) = text.split(':', -1).map { |piece| prefix(piece) }.join(':')
    end

    # Tilde expansion disabled (e.g. arithmetic operands): segments pass through.
    class NoTilde
      def initialize(_executor, segments)
        @segments = segments
      end

      def expand = @segments
    end
  end
end
