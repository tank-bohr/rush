# frozen_string_literal: true

RSpec.describe Rush::Builtins::Local do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('x' => 'global') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['local', *args], io).call

  it 'fails with status 2 outside a function' do
    expect(run('x=1').exitstatus).to eq(2)
  end

  context 'when inside a function scope' do
    before { state.begin_scope }

    it 'snapshots a bare name, restoring it when the scope ends' do
      run('x')
      env.assign('x', 'changed')
      state.end_scope
      expect(env.get('x')).to eq('global')
    end

    it 'assigns name=value and restores the prior value on scope end' do
      expect(run('x=local')).to be_success
      expect(env.get('x')).to eq('local')
      state.end_scope
      expect(env.get('x')).to eq('global')
    end

    it 'restores a previously-unset variable to unset' do
      run('fresh=1')
      state.end_scope
      expect(env.get('fresh')).to be_nil
    end

    it 'keeps the first snapshot when a name is declared twice' do
      run('x=one')
      run('x=two')
      state.end_scope
      expect(env.get('x')).to eq('global')
    end
  end
end
