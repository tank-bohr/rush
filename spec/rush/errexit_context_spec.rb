# frozen_string_literal: true

RSpec.describe Rush::ErrexitContext do
  subject(:context) { described_class.new(state) }

  let(:state) { Rush::ShellState.new }

  it 'returns successful and failing statuses when errexit is disabled' do
    failure = Rush::Status.new(7)

    expect(context.exit_on_error(Rush::Status.success)).to be_success
    expect(context.exit_on_error(failure)).to eq(failure)
  end

  it 'raises ExitSignal for an untested failing command under errexit' do
    state.options.set(:errexit, true)

    expect { context.exit_on_error(Rush::Status.new(7)) }
      .to raise_error(Rush::ExitSignal) { |signal| expect(signal.code).to eq(7) }
  end

  it 'suppresses errexit only while inside a tested scope' do
    state.options.set(:errexit, true)

    expect(context.scoped(true) { context.exit_on_error(Rush::Status.new(7)) }.exitstatus).to eq(7)
    expect { context.exit_on_error(Rush::Status.new(7)) }.to raise_error(Rush::ExitSignal)
  end

  it 'lets an untested nested scope override and then restore a tested scope' do
    state.options.set(:errexit, true)

    expect { context.scoped(true) { context.scoped(false) { context.exit_on_error(Rush::Status.new(7)) } } }
      .to raise_error(Rush::ExitSignal)

    expect(context.scoped(true) { context.exit_on_error(Rush::Status.new(7)) }.exitstatus).to eq(7)
  end
end
