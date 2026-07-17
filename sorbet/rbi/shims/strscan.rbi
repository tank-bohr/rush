# typed: true
# frozen_string_literal: true

# Hand-written shim for the StringScanner surface rush uses. Sorbet's bundled
# stdlib RBI leaves this C extension loose at key scanner boundaries; Steep gets
# the parallel declarations from sig/strscan_ext.rbs.
class StringScanner
  # rubocop:disable Style/OptionalBooleanParameter -- preserve Sorbet's bundled two-argument entry point
  sig { params(string: String, options: T.untyped).void }
  def initialize(string, options = false); end
  # rubocop:enable Style/OptionalBooleanParameter

  sig { params(pattern: T.any(Regexp, String)).returns(T.nilable(String)) }
  def scan(pattern); end

  sig { params(pattern: T.any(Regexp, String)).returns(T.nilable(Integer)) }
  def skip(pattern); end

  sig { returns(T.nilable(String)) }
  def getch; end

  sig { params(length: Integer).returns(String) }
  def peek(length); end

  sig { returns(T::Boolean) }
  def eos?; end

  sig { returns(StringScanner) }
  def unscan; end

  sig { returns(String) }
  def rest; end

  sig { returns(StringScanner) }
  def terminate; end

  sig { returns(Integer) }
  def charpos; end

  sig { returns(Integer) }
  def pos; end

  sig { returns(T.nilable(T::Array[T.nilable(String)])) }
  def captures; end
end
