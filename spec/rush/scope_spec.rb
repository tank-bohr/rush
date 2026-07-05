# frozen_string_literal: true

RSpec.describe Rush::Scope do
  let(:environment) { Rush::Environment.new({}) }

  it 'reports an internal invariant violation before pwd is seeded' do
    scope = described_class.new(environment)
    expect { scope.current_pwd }.to raise_error(Rush::Error, /PWD not seeded/)
  end

  it 'seeds a missing logical pwd without changing PWD or OLDPWD' do
    scope = described_class.new(environment)
    scope.seed_pwd('/seeded')
    expect([scope.current_pwd, scope.pwd, environment.get('PWD'), environment.get('OLDPWD')])
      .to eq(['/seeded', '/seeded', nil, nil])
  end

  it 'keeps an existing PWD when seeding' do
    env = Rush::Environment.new('PWD' => '/already')
    scope = described_class.new(env)
    scope.seed_pwd('/ignored')
    expect([scope.current_pwd, env.get('PWD'), env.get('OLDPWD')]).to eq(['/already', '/already', nil])
  end

  it 'moves the logical pwd while maintaining PWD and OLDPWD' do
    env = Rush::Environment.new('PWD' => '/old')
    scope = described_class.new(env)
    scope.move_to('/new')
    expect([scope.current_pwd, scope.pwd, env.get('PWD'), env.get('OLDPWD')])
      .to eq(['/new', '/new', '/new', '/old'])
  end

  it 'tracks function scope nesting' do
    scope = described_class.new(environment)
    expect(scope).not_to be_in_function
    scope.begin_scope
    expect(scope).to be_in_function
    scope.begin_scope
    scope.end_scope
    expect(scope).to be_in_function
    scope.end_scope
    expect(scope).not_to be_in_function
  end

  it 'restores an existing variable declared local in the current frame' do
    environment.assign('name', 'outer')
    scope = described_class.new(environment)
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'inner')
    scope.end_scope
    expect(environment.get('name')).to eq('outer')
  end

  it 'unsets a variable that was created as local in the current frame' do
    scope = described_class.new(environment)
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'inner')
    scope.end_scope
    expect(environment.get('name')).to be_nil
  end

  it 'removes the export mark when restoring a previously unset local' do
    environment.export('name')
    scope = described_class.new(environment)
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'inner')
    scope.end_scope
    expect([environment.get('name'), environment.exported]).to eq([nil, {}])
  end

  it 'keeps the first local snapshot when a variable is declared twice' do
    environment.assign('name', 'outer')
    scope = described_class.new(environment)
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'first-inner')
    scope.declare_local('name')
    environment.assign('name', 'second-inner')
    scope.end_scope
    expect(environment.get('name')).to eq('outer')
  end

  it 'restores nested local scopes independently' do
    environment.assign('name', 'outer')
    scope = described_class.new(environment)
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'middle')
    scope.begin_scope
    scope.declare_local('name')
    environment.assign('name', 'inner')
    scope.end_scope
    expect(environment.get('name')).to eq('middle')
    scope.end_scope
    expect(environment.get('name')).to eq('outer')
  end

  it 'raises when declaring a local outside a function frame' do
    scope = described_class.new(environment)
    expect { scope.declare_local('name') }.to raise_error(IndexError)
  end
end
