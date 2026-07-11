# typed: true
# frozen_string_literal: true

module Rush
  # Normal vs silent getopts error-mode formatting for bad options and missing
  # arguments.
  class GetoptsErrorMode
    extend T::Sig

    sig { returns(String) }
    attr_reader :missing_name

    sig { params(mode: Symbol).void }
    def initialize(mode)
      @missing_name = mode == :silent ? ':' : '?'
      @keep_optarg = mode == :silent
      @diagnostic = mode == :normal
    end

    sig { params(value: String).returns(T.nilable(String)) }
    def optarg(value)
      value if @keep_optarg
    end

    sig { params(text: String).returns(T.nilable(String)) }
    def message(text)
      text if @diagnostic
    end
  end

  # The getopts optstring operand (POSIX `getopts optstring name [arg...]`):
  # a leading colon selects silent error reporting, then each option letter,
  # `:`-suffixed when it requires an argument. Owns which letters are legal
  # and which take arguments; the parser keeps the cursor choreography.
  class Optstring
    extend T::Sig

    sig { returns(GetoptsErrorMode) }
    attr_reader :error_mode

    sig { params(text: String).void }
    def initialize(text)
      @error_mode = GetoptsErrorMode.new(text.start_with?(':') ? :silent : :normal)
      @letters = text.delete_prefix(':')
    end

    sig { params(option: String).returns(T::Boolean) }
    def valid?(option)
      !!(option != ':' && index(option))
    end

    sig { params(option: String).returns(T::Boolean) }
    def requires_argument?(option)
      position = index(option)
      !!(position && @letters[position + 1] == ':')
    end

    private

    sig { params(option: String).returns(T.nilable(Integer)) }
    def index(option)
      @letters.index(option)
    end
  end

  # Pure parser for one POSIX getopts step. It walks the argv words and the
  # hidden cluster cursor against the Optstring's semantics; the builtin
  # applies the returned variable updates.
  class GetoptsParser
    extend T::Sig

    # Sentinel optarg: leave OPTARG untouched (a real optarg is always a
    # String, so a Symbol can never collide with one).
    KEEP = :keep
    # The variable updates and status produced by one getopts step.
    Result = Data.define(:name, :optarg, :optind, :message, :exitstatus)
    # The option character plus the argv word it came from.
    Option = Data.define(:argument, :name)

    sig { params(state: GetoptsState, optstring: String, arguments: T::Array[String], optind: Integer).void }
    def initialize(state:, optstring:, arguments:, optind:)
      @state = state
      @optstring = Optstring.new(optstring)
      @error_mode = @optstring.error_mode
      @arguments = arguments
      @state.prepare(arguments, optind)
    end

    sig { returns(Result) }
    def call
      arg = @state.current(@arguments)
      return finish if !arg || arg == '-' || !arg.start_with?('-')
      return finish_double_dash if arg == '--'

      dispatch(option(arg))
    end

    private

    sig { params(option: Option).returns(Result) }
    def dispatch(option)
      name = option.name
      return invalid(option) unless @optstring.valid?(name)
      return argument_value(option) if @optstring.requires_argument?(name)

      found(name, '')
    end

    sig { params(name: String, value: String).returns(Result) }
    def found(name, value)
      consume_found(value)
      result(name, value, nil, 0)
    end

    sig { params(option: Option).returns(Result) }
    def invalid(option)
      name = option.name
      @state.consume_option(option.argument)
      error_result('?', name, "Illegal option -#{name}")
    end

    sig { params(option: Option).returns(Result) }
    def missing(option)
      consume_missing(option.argument)
      error_result(@error_mode.missing_name, option.name, "No arg for -#{option.name} option")
    end

    sig { returns(Result) }
    def finish
      @state.finish
      result('?', KEEP, nil, 1)
    end

    sig { returns(Result) }
    def finish_double_dash
      @state.finish_double_dash
      result('?', KEEP, nil, 1)
    end

    sig { params(value: String).void }
    def consume_found(value)
      current = T.must(@state.current(@arguments))
      return @state.consume_option(current) unless @optstring.requires_argument?(@state.option(current))

      attached_value?(current, value) ? @state.consume_attached_argument : @state.consume_detached_argument
    end

    sig { params(_argument: String).void }
    def consume_missing(_argument)
      @state.consume_attached_argument
    end

    sig { params(option: Option).returns(Result) }
    def argument_value(option)
      return found(option.name, attached_argument(option.argument)) if attached?(option.argument)

      next_argument ? found(option.name, T.must(next_argument)) : missing(option)
    end

    sig { params(name: String, silent_optarg: String, normal_message: String).returns(Result) }
    def error_result(name, silent_optarg, normal_message)
      result(name, @error_mode.optarg(silent_optarg), @error_mode.message(normal_message), 0)
    end

    sig { params(name: String, optarg: T.untyped, message: T.nilable(String), exitstatus: Integer).returns(Result) }
    def result(name, optarg, message, exitstatus)
      Result.new(name: name, optarg: optarg, optind: @state.optind, message: message, exitstatus: exitstatus)
    end

    sig { params(argument: String).returns(Option) }
    def option(argument)
      Option.new(argument: argument, name: @state.option(argument))
    end

    sig { params(argument: String).returns(String) }
    def attached_argument(argument)
      argument[(@state.cursor + 1)..].to_s
    end

    sig { params(argument: String, value: String).returns(T::Boolean) }
    def attached_value?(argument, value)
      !value.empty? && attached?(argument)
    end

    sig { params(argument: String).returns(T::Boolean) }
    def attached?(argument)
      @state.cursor < argument.length - 1
    end

    sig { returns(T.nilable(String)) }
    def next_argument
      @arguments[@state.current_index + 1]
    end
  end
end
