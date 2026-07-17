# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'

# Measures and ratchets Sorbet's typed-send counters without conflating them
# with the separate untyped-usage diagnostic count.
module SorbetCoverage
  class Error < StandardError; end

  # One raw-sorbet run, normalized into the counter and exact input scope that
  # the committed baseline/checker consume.
  class Measurement
    COUNTERS = {
      'typed_sends' => 'types.input.sends.typed',
      'total_sends' => 'types.input.sends.total',
      'untyped_usages' => 'types.input.untyped.usages'
    }.freeze

    attr_reader :sorbet_version, :typed_sends, :total_sends, :untyped_usages, :inputs

    def self.parse(metrics, file_table, version:)
      values = COUNTERS.transform_values { |name| metric(metrics, name) }
      new(version: version, counters: values, inputs: inputs(file_table))
    end

    def self.metric(metrics, name)
      entry = metrics.fetch('metrics').find { |row| row.fetch('name').end_with?(".#{name}") }
      raise Error, "Sorbet did not report #{name}" unless entry

      Integer(entry.fetch('value'))
    end

    def self.inputs(file_table)
      entries = file_table.fetch('files').map do |file|
        { 'path' => file.fetch('path'), 'sigil' => file.fetch('sigil', 'None') }
      end
      entries.sort_by { |entry| entry.fetch('path') }
    end

    def initialize(version:, counters:, inputs:)
      @sorbet_version = version
      @typed_sends = counters.fetch('typed_sends')
      @total_sends = counters.fetch('total_sends')
      @untyped_usages = counters.fetch('untyped_usages')
      @inputs = inputs
      validate_counters
    end

    def untyped_sends
      total_sends - typed_sends
    end

    def ratio
      typed_sends.fdiv(total_sends)
    end

    def summary
      format('Sorbet typed sends: %<typed>d/%<total>d (%<ratio>.2f%%); untyped sends: %<untyped>d; ' \
             'untyped usages: %<usages>d; inputs: %<inputs>d',
             typed: typed_sends, total: total_sends, ratio: ratio * 100,
             untyped: untyped_sends, usages: untyped_usages, inputs: inputs.length)
    end

    def baseline_hash
      {
        'schema' => 1,
        'sorbet_version' => sorbet_version,
        'scope' => { 'inputs' => inputs },
        'observed' => {
          'typed_sends' => typed_sends,
          'total_sends' => total_sends,
          'untyped_sends' => untyped_sends,
          'untyped_usages' => untyped_usages
        }
      }
    end

    private

    def validate_counters
      raise Error, 'total sends must be positive' unless total_sends.positive?
      raise Error, 'Sorbet counters must be nonnegative' if typed_sends.negative? || untyped_usages.negative?
      raise Error, 'typed sends exceed total sends' if typed_sends > total_sends
    end
  end

  # The reviewed ratchet: tool version and exact path/sigil scope must match;
  # both the absolute untyped-send gap and typed ratio may only improve.
  class Check
    SUPPORTED_SCHEMA = 1

    def initialize(measurement, baseline, budgets)
      @measurement = measurement
      @baseline = baseline
      @budgets = budgets
    end

    def failures
      schema = schema_failures
      return schema unless schema.empty?

      version_failures + scope_failures + gap_failures + ratio_failures
    end

    private

    def schema_failures
      schemas = [@baseline.fetch('schema'), @budgets.fetch('schema')]
      return [] if schemas.all?(SUPPORTED_SCHEMA)

      ["unsupported Sorbet coverage schema: baseline=#{schemas[0].inspect}, budgets=#{schemas[1].inspect}"]
    end

    def version_failures
      expected = @baseline.fetch('sorbet_version')
      return [] if @measurement.sorbet_version == expected

      ["Sorbet version differs from baseline: current=#{@measurement.sorbet_version.inspect}, " \
       "baseline=#{expected.inspect}"]
    end

    def scope_failures
      baseline_inputs = @baseline.fetch('scope').fetch('inputs')
      return [] if @measurement.inputs == baseline_inputs

      [scope_message(baseline_inputs)]
    end

    def scope_message(baseline_inputs)
      baseline = input_map(baseline_inputs)
      current = input_map(@measurement.inputs)
      details = scope_details(baseline, current)
      return 'Sorbet input scope differs from baseline' if details.empty?

      "Sorbet input scope differs from baseline: #{details}"
    end

    def input_map(inputs)
      inputs.to_h { |entry| [entry.fetch('path'), entry.fetch('sigil')] }
    end

    def scope_details(baseline, current)
      added = list('added', current.keys - baseline.keys)
      removed = list('removed', baseline.keys - current.keys)
      changed = list('sigils', changed_sigils(baseline, current))
      [added, removed, changed].compact.join('; ')
    end

    def changed_sigils(baseline, current)
      (baseline.keys & current.keys).filter_map do |path|
        "#{path}:#{baseline.fetch(path)}->#{current.fetch(path)}" unless baseline.fetch(path) == current.fetch(path)
      end
    end

    def list(label, values)
      "#{label}=#{values.sort.join(',')}" unless values.empty?
    end

    def gap_failures
      maximum = @budgets.fetch('maximum_untyped_sends')
      return [] if @measurement.untyped_sends <= maximum

      ["Sorbet untyped sends #{@measurement.untyped_sends} exceed the budget #{maximum}"]
    end

    def ratio_failures
      minimum = @budgets.fetch('minimum_typed_ratio')
      return [] if ratio_pass?(minimum)

      [ratio_failure_message(minimum)]
    end

    def ratio_pass?(minimum)
      @measurement.typed_sends * minimum.fetch('total_sends') >=
        minimum.fetch('typed_sends') * @measurement.total_sends
    end

    def ratio_failure_message(minimum)
      current = format('%.4f%%', @measurement.ratio * 100)
      expected = format('%.4f%%', minimum.fetch('typed_sends').fdiv(minimum.fetch('total_sends')) * 100)
      "Sorbet typed-send ratio #{current} is below the budget #{expected}"
    end
  end

  # Executes the same raw binary as the static gate and asks it for counters plus
  # file-table JSON in one pass. Output is replayed so type errors stay visible.
  class Runner
    def initialize(binary:, stdout: $stdout, stderr: $stderr)
      @binary = binary
      @stdout = stdout
      @stderr = stderr
    end

    def measure
      version = capture_version
      Dir.mktmpdir('rush-sorbet-coverage') { |directory| measure_in(directory, version) }
    end

    private

    def measure_in(directory, version)
      metrics_path, table_path = output_paths(directory)
      capture('--track-untyped=everywhere', "--metrics-file=#{metrics_path}",
              "--print=file-table-json:#{table_path}")
      Measurement.parse(load(metrics_path), load(table_path), version: version)
    end

    def output_paths(directory)
      [File.join(directory, 'metrics.json'), File.join(directory, 'files.json')]
    end

    def load(path)
      JSON.parse(File.read(path))
    end

    def capture_version
      stdout, stderr, status = Open3.capture3(@binary, '--version')
      raise Error, "Sorbet --version failed: #{stderr}" unless status.success?

      stdout.strip
    end

    def capture(*arguments)
      stdout, stderr, status = Open3.capture3(@binary, *arguments)
      @stdout.print(stdout)
      @stderr.print(stderr)
      raise Error, "Sorbet type check failed with status #{status.exitstatus}" unless status.success?

      nil
    end
  end

  module_function

  def load_json(path)
    JSON.parse(File.read(path))
  end

  def check!(binary:, baseline_path:, budgets_path:)
    measurement = Runner.new(binary: binary).measure
    failures = Check.new(measurement, load_json(baseline_path), load_json(budgets_path)).failures
    puts measurement.summary
    abort failures.join("\n") unless failures.empty?
  end

  def record!(binary:, baseline_path:)
    measurement = Runner.new(binary: binary).measure
    File.write(baseline_path, "#{JSON.pretty_generate(measurement.baseline_hash)}\n")
    puts measurement.summary
    puts "Recorded Sorbet coverage scope and observations in #{baseline_path}; budgets unchanged"
  end
end
