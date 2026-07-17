# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require_relative '../../../tasks/sorbet_coverage'

RSpec.describe SorbetCoverage::Runner do
  it 'runs version and type-check probes, replays diagnostics, and returns the measurement' do
    stdout = StringIO.new
    stderr = StringIO.new
    result = described_class.new(binary: fake_sorbet, stdout: stdout, stderr: stderr).measure

    expect([result.sorbet_version, result.typed_sends, result.total_sends, result.untyped_usages])
      .to eq(['Sorbet typechecker fake', 90, 100, 12])
    expect([stdout.string, stderr.string]).to eq(["No errors! Great job.\n", "fake diagnostic\n"])
  end

  it 'fails closed when the version probe fails' do
    runner = described_class.new(binary: fake_sorbet(version_status: 2))
    expect { runner.measure }.to raise_error(SorbetCoverage::Error, /Sorbet --version failed: version failed/)
  end

  it 'replays a failed type check before reporting its status' do
    stderr = StringIO.new
    runner = described_class.new(binary: fake_sorbet(check_status: 3), stdout: StringIO.new, stderr: stderr)

    expect { runner.measure }.to raise_error(SorbetCoverage::Error, /type check failed with status 3/)
    expect(stderr.string).to eq("fake diagnostic\n")
  end

  it 'records baseline observations without accepting a budgets path' do
    Dir.mktmpdir do |directory|
      baseline = File.join(directory, 'baseline.json')
      action = -> { SorbetCoverage.record!(binary: fake_sorbet, baseline_path: baseline) }
      matcher = output(/Recorded Sorbet coverage scope and observations/).to_stdout.and(
        output("fake diagnostic\n").to_stderr
      )
      expect(&action).to matcher
      expect(JSON.parse(File.read(baseline)).fetch('observed')).to eq(
        'typed_sends' => 90, 'total_sends' => 100, 'untyped_sends' => 10, 'untyped_usages' => 12
      )
    end
  end

  it 'aborts the check with the reviewed-budget failure' do
    Dir.mktmpdir do |directory|
      baseline, budgets = write_check_files(directory, maximum: 9)
      action = lambda do
        SorbetCoverage.check!(binary: fake_sorbet, baseline_path: baseline, budgets_path: budgets)
      end
      assertion = lambda do
        expect(&action).to raise_error(SystemExit, /Sorbet untyped sends 10 exceed the budget 9/)
      end
      matcher = output(%r{Sorbet typed sends: 90/100}).to_stdout.and(
        output(/fake diagnostic.*untyped sends 10 exceed/m).to_stderr
      )
      expect(&assertion).to matcher
    end
  end

  def fake_sorbet(version_status: 0, check_status: 0)
    directory = Dir.mktmpdir('fake-sorbet')
    path = File.join(directory, 'sorbet')
    File.write(path, fake_source(version_status, check_status))
    File.chmod(0o755, path)
    path
  end

  def fake_source(version_status, check_status)
    <<~RUBY
      #!/usr/bin/env ruby
      require 'json'
      if ARGV == ['--version']
        warn 'version failed' unless #{version_status}.zero?
        puts 'Sorbet typechecker fake' if #{version_status}.zero?
        exit #{version_status}
      end
      metrics = ARGV.find { |arg| arg.start_with?('--metrics-file=') }.split('=', 2).last
      files = ARGV.find { |arg| arg.start_with?('--print=file-table-json:') }.split(':', 2).last
      rows = [['types.input.sends.typed', 90], ['types.input.sends.total', 100],
              ['types.input.untyped.usages', 12]].map { |name, value| { 'name' => "fake.\#{name}", 'value' => value } }
      File.write(metrics, JSON.generate('metrics' => rows))
      File.write(files, JSON.generate('files' => [{ 'path' => './lib/a.rb', 'sigil' => 'True' }]))
      puts 'No errors! Great job.'
      warn 'fake diagnostic'
      exit #{check_status}
    RUBY
  end

  def write_check_files(directory, maximum:)
    baseline = File.join(directory, 'baseline.json')
    budgets = File.join(directory, 'budgets.json')
    File.write(baseline, JSON.generate(baseline_hash))
    budget = { 'schema' => 1, 'maximum_untyped_sends' => maximum,
               'minimum_typed_ratio' => { 'typed_sends' => 90, 'total_sends' => 100 } }
    File.write(budgets, JSON.generate(budget))
    [baseline, budgets]
  end

  def baseline_hash
    {
      'schema' => 1,
      'sorbet_version' => 'Sorbet typechecker fake',
      'scope' => { 'inputs' => [{ 'path' => './lib/a.rb', 'sigil' => 'True' }] },
      'observed' => { 'typed_sends' => 90, 'total_sends' => 100, 'untyped_sends' => 10,
                      'untyped_usages' => 12 }
    }
  end
end
