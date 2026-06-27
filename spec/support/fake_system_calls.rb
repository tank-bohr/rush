# frozen_string_literal: true

# In-memory stand-in for Rush::SystemCalls used by integration and builtin
# specs: stdin/stdout/stderr are StringIO so output is asserted without touching
# the real OS. Process-spawning paths are exercised separately with doubles.
class FakeSystemCalls
  def initialize(stdin: '')
    @stdin = StringIO.new(stdin)
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  attr_reader :stdin, :stdout, :stderr
end
