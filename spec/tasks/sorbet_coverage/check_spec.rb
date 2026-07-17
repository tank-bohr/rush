# frozen_string_literal: true

require_relative '../../../tasks/sorbet_coverage'

RSpec.describe SorbetCoverage::Check do
  it 'accepts matching version/scope with both gap and ratio inside their budgets' do
    expect(check.failures).to eq([])
  end

  it 'rejects unsupported schemas before reading their obsolete shape' do
    failure = 'unsupported Sorbet coverage schema: baseline=2, budgets=3'
    result = check(baseline_hash: { 'schema' => 2 }, budget_hash: { 'schema' => 3 })
    expect(result.failures).to eq([failure])
  end

  it 'requires an explicit baseline review when the Sorbet binary changes' do
    current = measurement(version: 'new Sorbet')
    expect(check(current: current).failures).to eq(
      ['Sorbet version differs from baseline: current="new Sorbet", baseline="Sorbet typechecker test-version"']
    )
  end

  it 'reports added, removed, and changed-sigil inputs as scope drift' do
    current_inputs = [
      { 'path' => './lib/a.rb', 'sigil' => 'False' },
      { 'path' => './lib/new.rb', 'sigil' => 'True' }
    ]

    message = 'Sorbet input scope differs from baseline: added=./lib/new.rb; ' \
              'removed=./lib/generated.rb; sigils=./lib/a.rb:True->False'
    expect(check(current: measurement(inputs: current_inputs)).failures).to eq([message])
  end

  it 'ratchets the absolute untyped-send gap even when the ratio still passes' do
    current = measurement(typed: 91, total: 102)
    loose_ratio = budgets.merge('minimum_typed_ratio' => { 'typed_sends' => 1, 'total_sends' => 2 })
    expect(check(current: current, budget_hash: loose_ratio).failures).to eq(
      ['Sorbet untyped sends 11 exceed the budget 10']
    )
  end

  it 'ratchets the exact rational ratio even when the absolute gap still passes' do
    current = measurement(typed: 890, total: 1000)
    loose_gap = budgets.merge('maximum_untyped_sends' => 200)
    expect(check(current: current, budget_hash: loose_gap).failures).to eq(
      ['Sorbet typed-send ratio 89.0000% is below the budget 90.0000%']
    )
  end

  it 'parses counter metrics and normalizes missing sigils in path order' do
    metrics = { 'metrics' => [
      { 'name' => 'prefix.types.input.sends.total', 'value' => 100 },
      { 'name' => 'prefix.types.input.untyped.usages', 'value' => 12 },
      { 'name' => 'prefix.types.input.sends.typed', 'value' => 90 }
    ] }
    files = { 'files' => [
      { 'path' => './lib/generated.rb' },
      { 'path' => './lib/a.rb', 'sigil' => 'True' }
    ] }

    result = SorbetCoverage::Measurement.parse(metrics, files, version: version)
    expect([result.typed_sends, result.total_sends, result.untyped_sends, result.untyped_usages, result.inputs])
      .to eq([90, 100, 10, 12, inputs])
  end

  it 'fails closed when a required Sorbet metric is absent' do
    expect { SorbetCoverage::Measurement.parse({ 'metrics' => [] }, { 'files' => [] }, version: version) }
      .to raise_error(SorbetCoverage::Error, /types\.input\.sends\.typed/)
  end

  it 'rejects an undefined zero-send ratio and invalid counter ranges' do
    expect { measurement(typed: 0, total: 0) }
      .to raise_error(SorbetCoverage::Error, 'total sends must be positive')
    expect { measurement(typed: -1) }
      .to raise_error(SorbetCoverage::Error, 'Sorbet counters must be nonnegative')
    expect { measurement(typed: 101) }
      .to raise_error(SorbetCoverage::Error, 'typed sends exceed total sends')
  end

  it 'records observations and scope without embedding or changing budgets' do
    expect(measurement.baseline_hash).to eq(
      'schema' => 1,
      'sorbet_version' => version,
      'scope' => { 'inputs' => inputs },
      'observed' => {
        'typed_sends' => 90, 'total_sends' => 100, 'untyped_sends' => 10, 'untyped_usages' => 12
      }
    )
  end

  def check(current: nil, baseline_hash: nil, budget_hash: nil)
    described_class.new(current || measurement, baseline_hash || baseline, budget_hash || budgets)
  end

  def measurement(**overrides)
    values = { version: version, typed: 90, total: 100, usages: 12, inputs: inputs }.merge(overrides)
    counters = { 'typed_sends' => values.fetch(:typed), 'total_sends' => values.fetch(:total),
                 'untyped_usages' => values.fetch(:usages) }
    SorbetCoverage::Measurement.new(version: values.fetch(:version), counters: counters, inputs: values.fetch(:inputs))
  end

  def version
    'Sorbet typechecker test-version'
  end

  def inputs
    [{ 'path' => './lib/a.rb', 'sigil' => 'True' },
     { 'path' => './lib/generated.rb', 'sigil' => 'None' }]
  end

  def baseline
    measurement.baseline_hash
  end

  def budgets
    {
      'schema' => 1,
      'maximum_untyped_sends' => 10,
      'minimum_typed_ratio' => { 'typed_sends' => 90, 'total_sends' => 100 }
    }
  end
end
