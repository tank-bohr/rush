# frozen_string_literal: true

RSpec.describe Rush::GetoptsState do
  subject(:state) { described_class.new }

  it 'starts at the first argument, cursor past the dash, OPTIND 1' do
    expect([state.current_index, state.cursor, state.optind]).to eq([0, 1, 1])
  end

  it 'walks a cluster: cursor advances mid-argument while OPTIND already points past it' do
    state.prepare(['-ab', 'c'], 1)
    expect(state.option('-ab')).to eq('a')
    state.consume_option('-ab')
    expect([state.current_index, state.cursor, state.optind]).to eq([0, 2, 2])
    expect(state.option('-ab')).to eq('b')
    state.consume_option('-ab')
    expect([state.current_index, state.cursor, state.optind]).to eq([1, 1, 2])
  end

  it 'publishes OPTIND past the cluster argument wherever it sits' do
    state.prepare(['-a', '-bc'], 1)
    state.consume_final_option
    state.prepare(['-a', '-bc'], 2)
    state.consume_option('-bc')
    expect(state.optind).to eq(3)
  end

  it 'steps past an attached argument (-avalue) rewinding the cursor' do
    state.prepare(['-avalue', 'rest'], 1)
    state.consume_attached_argument
    expect([state.current_index, state.cursor, state.optind]).to eq([1, 1, 2])
  end

  it 'steps past a detached argument (-a value) rewinding the cursor' do
    state.prepare(['-a', 'value', 'rest'], 1)
    state.consume_detached_argument
    expect([state.current_index, state.cursor, state.optind]).to eq([2, 1, 3])
  end

  it 'rewinds the cursor when it finishes mid-cluster' do
    state.prepare(['-ab'], 1)
    state.consume_option('-ab')
    state.finish
    expect([state.cursor, state.optind]).to eq([1, 1])
  end

  it 'consumes the -- terminator' do
    state.prepare(['--', 'x'], 1)
    state.finish_double_dash
    expect([state.current_index, state.optind]).to eq([1, 2])
  end

  it 'keeps its hidden cursor while the arguments and OPTIND are unchanged' do
    state.prepare(['-ab'], 1)
    state.consume_option('-ab')
    state.prepare(['-ab'], 2)
    expect(state.cursor).to eq(2)
  end

  it 'resets when the argument vector changes' do
    state.prepare(['-ab'], 1)
    state.consume_option('-ab')
    state.prepare(['-xy'], 2)
    expect([state.current_index, state.cursor, state.optind]).to eq([1, 1, 2])
  end

  it 'resets when the user rewinds OPTIND' do
    state.prepare(['-a', '-b'], 1)
    state.consume_final_option
    state.prepare(['-a', '-b'], 1)
    expect([state.current_index, state.optind]).to eq([0, 1])
  end

  it 'clamps a zero OPTIND to the first argument' do
    state.prepare(['-a'], 0)
    expect(state.current_index).to eq(0)
  end

  it 'reads the current argument through the cursor index' do
    state.prepare(['-a', 'x'], 1)
    expect(state.current(['-a', 'x'])).to eq('-a')
  end
end
