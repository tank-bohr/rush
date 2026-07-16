# frozen_string_literal: true

RSpec.describe Rush::Builtins::Base do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }
  let(:executor) { instance_double(Rush::Executor) }

  let(:subclass) do
    Class.new(described_class) do
      def call
        stdout.puts('out')
        stderr.puts('err')
        [executor, operands, success.exitstatus, failure.exitstatus, failure(2).exitstatus]
      end

      def numeric(text, min:)
        numeric_operand(text, min: min)
      end

      def numeric_default(text)
        numeric_operand(text)
      end
    end
  end

  def builtin(argv = %w[name a b])
    subclass.new(executor, argv, io)
  end

  it 'raises until a subclass implements #call' do
    expect { described_class.new(executor, [], io).call }.to raise_error(NotImplementedError)
  end

  it 'exposes executor, operands, streams and status helpers to subclasses' do
    result = builtin.call

    expect(result).to eq([executor, %w[a b], 0, 1, 2])
    expect(system.stdout.string).to eq("out\n")
    expect(system.stderr.string).to eq("err\n")
  end

  it 'parses numeric operands with optional plus and surrounding blanks' do
    expect(builtin.numeric_default('  +42  ')).to eq(42)
  end

  it 'accepts zero by default and enforces a custom minimum' do
    expect(builtin.numeric_default('0')).to eq(0)
    expect(builtin.numeric('1', min: 1)).to eq(1)
  end

  it 'accepts INT_MAX but rejects overflow' do
    expect(builtin.numeric_default('2147483647')).to eq(2_147_483_647)
    expect { builtin.numeric_default('2147483648') }
      .to raise_error(Rush::BuiltinError, 'name: Illegal number: 2147483648')
  end

  it 'rejects negative, below-minimum and non-decimal operands' do
    expect { builtin.numeric_default('-1') }.to raise_error(Rush::BuiltinError, 'name: Illegal number: -1')
    expect { builtin.numeric('0', min: 1) }.to raise_error(Rush::BuiltinError, 'name: Illegal number: 0')
    expect { builtin.numeric_default('12x') }.to raise_error(Rush::BuiltinError, 'name: Illegal number: 12x')
  end

  it 'prefers the invocation environment over the exported variables' do
    with_env = subclass.new(executor, %w[name], io, { 'TMP' => 'prefix' })
    expect(with_env.__send__(:command_environment)).to eq({ 'TMP' => 'prefix' })
  end

  it 'assembles the exported variables when no invocation environment rode in' do
    state = Rush::ShellState.new(environment: Rush::Environment.new({}))
    state.variables.assign('EXP', 'v')
    state.variables.export('EXP')
    real = Rush::Executor.new(system: system, state: state)

    expect(subclass.new(real, %w[name], io).__send__(:command_environment)).to eq({ 'EXP' => 'v' })
  end
end
