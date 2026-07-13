# frozen_string_literal: true

RSpec.describe Rush::CommandResolution do
  let(:functions) { Rush::FunctionTable.new }
  let(:builtins) { Rush::Builtins.default_registry }

  def resolve(name)
    described_class.for_execution(name, functions, builtins)
  end

  it 'carries the complete execution policy for every command kind' do
    functions.define('f', Rush::AST::SimpleCommand.new([], [], []))
    kind = described_class::Kind
    lifetime = described_class::AssignmentLifetime
    redirect = described_class::RedirectFailure
    expected = {
      ':' => [kind::SPECIAL_BUILTIN, lifetime::PERSISTENT, redirect::FATAL],
      'f' => [kind::FUNCTION, lifetime::TEMPORARY, redirect::ORDINARY],
      'echo' => [kind::BUILTIN, lifetime::TEMPORARY, redirect::ORDINARY],
      'missing' => [kind::EXTERNAL, lifetime::ENVIRONMENT, redirect::ORDINARY]
    }

    actual = expected.keys.to_h do |name|
      resolution = resolve(name)
      [name, [resolution.kind, resolution.assignment_lifetime, resolution.redirect_failure]]
    end
    expect(actual).to eq(expected)
  end

  it 'requires a registered implementation before classifying a special name as a builtin' do
    empty = Rush::Builtins::Registry.new
    functions.define(':', Rush::AST::SimpleCommand.new([], [], []))

    resolution = described_class.for_execution(':', functions, empty)
    expect([resolution.kind, described_class.special_builtin?(':', empty)])
      .to eq([described_class::Kind::FUNCTION, false])
  end

  it 'lets a registered special builtin outrank a function with the same name' do
    functions.define(':', Rush::AST::SimpleCommand.new([], [], []))
    resolution = resolve(':')

    expect([resolution.kind, resolution.builtin?, resolution.function?,
            resolution.persistent_assignments?, resolution.fatal_redirect?])
      .to eq([described_class::Kind::SPECIAL_BUILTIN, true, false, true, true])
  end

  it 'keeps ordinary builtin and external policies nonfatal and nonpersistent' do
    builtin = resolve('echo')
    external = resolve('missing')

    expect([builtin.builtin?, builtin.persistent_assignments?, builtin.fatal_redirect?,
            external.builtin?, external.function?, external.fatal_redirect?])
      .to eq([true, false, false, false, false, false])
  end

  it 'uses an immutable, exhaustive policy map for the finite command kinds' do
    policies = described_class::POLICIES

    expect(policies.keys).to match_array(described_class::Kind.values)
    expect { policies.fetch(described_class::Kind::FUNCTION) << described_class::RedirectFailure::FATAL }
      .to raise_error(FrozenError)
  end

  it 'keeps the shared special-builtin catalog complete against the default registry' do
    missing = described_class::SPECIAL_BUILTINS.reject { |name| builtins.key?(name) }
    regular = Rush::Builtins::DEFAULTS.keys.reject { |name| described_class.special_builtin?(name, builtins) }

    expect(missing).to be_empty
    expect(regular).to include('echo', 'command', 'type')
  end
end
