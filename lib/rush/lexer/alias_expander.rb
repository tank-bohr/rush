# typed: true
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
      extend T::Sig

      # A resolved alias replacement ready to splice into the scanner.
      class Replacement
        extend T::Sig

        sig { returns(String) }
        attr_reader :name, :value

        sig { params(name: String, value: String).void }
        def initialize(name, value)
          @name = name
          @value = value
        end

        sig { params(parent: StringScanner).returns(Frame) }
        def frame(parent)
          Frame.new(name, value, parent)
        end
      end

      # One active replacement and the scanner it temporarily covers.
      class Frame
        extend T::Sig

        sig { returns(String) }
        attr_reader :name, :value

        sig { returns(StringScanner) }
        attr_reader :parent

        sig { params(name: String, value: String, parent: StringScanner).void }
        def initialize(name, value, parent)
          @name = name
          @value = value
          @parent = parent
        end

        sig { returns(T::Boolean) }
        def trailing_blank?
          value.end_with?(' ', "\t")
        end
      end

      sig { params(table: T.nilable(AliasTable)).void }
      def initialize(table)
        @table = table
        @frames = []
        @check_next = false
      end

      # The replacement text when `word` is an alias eligible to expand here, else
      # nil. Eligible means command position or a pending trailing-blank carry.
      sig { params(word: AST::Word, command_position: T::Boolean).returns(T.nilable(Replacement)) }
      def expand(word, command_position)
        name = word.literal_name
        return unless name && eligible?(command_position)

        table = @table
        return unless table

        enter(table, name)
      end

      # Stash the scanner a replacement was spliced over; restore it once the
      # replacement is fully read, dropping the alias from the active set and, if
      # its value ended in a blank, marking the following word eligible too (OR so
      # an inner blank-ending alias still chains past an outer one).
      sig { params(replacement: Replacement, scanner: StringScanner).void }
      def push(replacement, scanner)
        @frames.push(replacement.frame(scanner))
      end

      sig { returns(T::Boolean) }
      def nested?
        @frames.any?
      end

      sig { returns(T.nilable(StringScanner)) }
      def pop
        frame = @frames.fetch(-1)
        @frames.pop
        @check_next = true if frame.trailing_blank?
        frame.parent
      end

      # A real (non-spliced) token was emitted: spend the one-shot carry.
      sig { void }
      def spend
        @check_next = false
      end

      private

      # Eligible position: aliases are defined and the word sits in command
      # position, or a pending trailing-blank carry makes it eligible here.
      sig { params(command_position: T::Boolean).returns(T::Boolean) }
      def eligible?(command_position)
        command_position || @check_next
      end

      sig { params(table: AliasTable, name: String).returns(T.nilable(Replacement)) }
      def enter(table, name)
        value = table.value(name)
        return if !value || active?(name)

        Replacement.new(name, value)
      end

      sig { params(name: String).returns(T::Boolean) }
      def active?(name)
        @frames.any? { |frame| frame.name == name }
      end
    end
  end
end
