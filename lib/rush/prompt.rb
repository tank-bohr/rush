# typed: true
# frozen_string_literal: true

module Rush
  # The interactive prompt strings (POSIX 2.5.3): PS1 and PS2 are re-read from
  # the shell variables at every prompt — so assignments take effect
  # mid-session — and subjected to parameter expansion ONLY: $name and ${...}
  # forms expand, while command substitution, arithmetic, tilde, quoting and
  # backslashes all stay literal. Defaults: '$ ' ('# ' for a privileged shell)
  # and '> '. A malformed value (unterminated ${, a failing ${x?} form) falls
  # back to the raw string: a prompt must never break the session.
  class Prompt
    extend T::Sig

    # Scans a prompt value into literal and parameter segments: $name and
    # ${...} become ParamSegments via the shared ParamScanner; any other
    # character is literal text.
    class Text
      extend T::Sig

      sig { params(text: String).void }
      def initialize(text)
        @scanner = StringScanner.new(text)
        @segments = T.let([], T::Array[AST::WordSegment[T.untyped]])
        @literal = +''
      end

      sig { returns(AST::Word) }
      def word
        step until @scanner.eos?
        flush
        AST::Word.new(@segments)
      end

      private

      sig { void }
      def step
        char = T.must(@scanner.getch)
        char == '$' ? dollar : @literal << char
      end

      sig { void }
      def dollar
        ref = Lexer::ParamScanner.new(@scanner).read
        ref ? push(AST::ParamSegment.new(ref, false)) : @literal << '$'
      end

      sig { params(segment: AST::WordSegment[T.untyped]).void }
      def push(segment)
        flush
        @segments << segment
      end

      sig { void }
      def flush
        return if @literal.empty?

        @segments << AST::LiteralSegment.new(@literal, false)
        @literal = +''
      end
    end

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
    end

    sig { returns(String) }
    def primary
      render('PS1', @executor.system.privileged? ? '# ' : '$ ')
    end

    sig { returns(String) }
    def continuation
      render('PS2', '> ')
    end

    private

    sig { params(name: String, default: String).returns(String) }
    def render(name, default)
      expand(@executor.state.variables.get(name) || default)
    end

    sig { params(raw: String).returns(String) }
    def expand(raw)
      @executor.expander.expand_value(Text.new(raw).word, tilde: :none)
    rescue ParseError, ExpansionError
      raw
    end
  end
end
