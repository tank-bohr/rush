# frozen_string_literal: true

module Rush
  class Lexer
    # POSIX 2.3.1 alias substitution at lex time. Decides whether a word scanned
    # in command position is an alias to splice, guarding against re-expanding an
    # alias within its own replacement (recursion), and tracking the trailing
    # <blank> rule: a replacement ending in a blank makes the *next* word eligible
    # too, even though it sits in argument position. Eligibility carries into the
    # first word of a replacement, so `b` -> `hello` -> `world` chains. It also
    # owns the stack of input scanners pushed beneath the replacements being read.
    class AliasExpander
      def initialize(table)
        @table = table
        @active = []
        @parents = []
        @check_next = false
      end

      # The replacement text when `word` is an alias eligible to expand here, else
      # nil. Eligible means command position or a pending trailing-blank carry.
      def expand(word, command_position)
        name = word.literal_name
        return nil unless name && eligible?(command_position)

        enter(name)
      end

      # Stash the scanner a replacement was spliced over; restore it once the
      # replacement is fully read, dropping the alias from the active set and, if
      # its value ended in a blank, marking the following word eligible too (OR so
      # an inner blank-ending alias still chains past an outer one).
      def push(scanner) = @parents.push(scanner)

      def nested? = @parents.any?

      def pop
        _name, value = @active.pop
        @check_next = true if value.end_with?(' ', "\t")
        @parents.pop
      end

      # A real (non-spliced) token was emitted: spend the one-shot carry.
      def spend = @check_next = false

      private

      # Eligible position: aliases are defined and the word sits in command
      # position, or a pending trailing-blank carry makes it eligible here.
      def eligible?(command_position) = @table && (command_position || @check_next)

      def enter(name)
        value = @table.value(name)
        return nil if !value || @active.any? { |active, _| active == name }

        @active.push([name, value])
        value
      end
    end
  end
end
