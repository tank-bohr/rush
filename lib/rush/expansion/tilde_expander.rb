# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Tilde expansion (step 1): a leading unquoted `~` or `~name` in a word's
    # first literal segment becomes $HOME or the named user's home directory. It
    # is left untouched when there is no such user, or when HOME is unset for a
    # bare `~`. This base handles the leading form; AssignmentTilde extends it to
    # also expand after each unquoted colon, and NoTilde disables it entirely.
    class TildeExpander
      extend T::Sig

      sig { params(executor: Executor, segments: T::Array[AST::AnySegment]).void }
      def initialize(executor, segments)
        @executor = executor
        @segments = segments
      end

      sig { returns(T::Array[AST::AnySegment]) }
      def expand
        head = @segments.first
        return @segments unless head.is_a?(AST::LiteralSegment)

        text = head.literal_value
        text ? replace_head(head, text) : @segments
      end

      private

      # Only a literal head carries a rewritable tilde prefix (literal_value is
      # nil for every dynamic segment), so the head is already narrowed above.
      sig { params(head: AST::LiteralSegment, text: String).returns(T::Array[AST::AnySegment]) }
      def replace_head(head, text)
        rewritten = rewrite(text)
        return @segments if rewritten == text

        @segments.dup.tap { |segments| segments[0] = head.with_value(rewritten) }
      end

      sig { params(text: String).returns(String) }
      def rewrite(text)
        prefix(text)
      end

      sig { params(text: String).returns(String) }
      def prefix(text)
        return text unless text.start_with?('~')

        name, rest = split(text.delete_prefix('~'))
        home = resolve(name)
        home ? home + rest : text
      end

      sig { params(body: String).returns([String, String]) }
      def split(body)
        name, slash, rest = body.partition('/')
        slash.empty? ? [body, ''] : [name, slash + rest]
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def resolve(name)
        return @executor.state.variables.get('HOME') if name.empty?

        @executor.system.home_dir(name)
      end
    end

    # Assignment context (PATH=~/bin:~root/x): the leading tilde plus one after
    # each unquoted colon, so every colon-separated piece gets the ~ treatment.
    class AssignmentTilde < TildeExpander
      extend T::Sig

      private

      sig { params(text: String).returns(String) }
      def rewrite(text)
        return text unless expandable?(text)

        text.split(':', -1).map { |piece| prefix(piece) }.join(':')
      end

      sig { params(text: String).returns(T::Boolean) }
      def expandable?(text)
        text.start_with?('~') || text.include?(':~')
      end
    end

    # Tilde expansion disabled (e.g. arithmetic operands): segments pass through.
    class NoTilde
      extend T::Sig

      sig { params(_executor: Executor, segments: T::Array[AST::AnySegment]).void }
      def initialize(_executor, segments)
        @segments = segments
      end

      sig { returns(T::Array[AST::AnySegment]) }
      def expand
        @segments
      end
    end
  end
end
