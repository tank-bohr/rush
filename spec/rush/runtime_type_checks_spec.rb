# frozen_string_literal: true

require 'open3'
require 'tempfile'

require_relative '../../lib/rush/runtime_type_checks'

RSpec.describe Rush::RuntimeTypeChecks do
  let(:probe_source) do
    <<~RUBY
      require 'rush/runtime_type_checks'
      Rush::RuntimeTypeChecks.configure
      class RuntimeCheckProbe
        extend T::Sig
        sig { params(value: Integer).void }
        def self.call(value); end
      end
      RuntimeCheckProbe.call('wrong')
      puts 'accepted'
    RUBY
  end

  it 'disables call validation by default in a configured production process' do
    expect(probe(nil)).to eq(['accepted', true])
  end

  it 'retains call validation for an explicitly requested diagnostic process' do
    output, success = probe('1')

    expect(output).to include('Expected type Integer')
    expect(success).to be(false)
  end

  it 'leaves runtime validation enabled when rush is loaded as a library' do
    source = probe_source.sub("require 'rush/runtime_type_checks'\nRush::RuntimeTypeChecks.configure", "require 'rush'")
    output, success = probe(nil, source)

    expect(output).to include('Expected type Integer')
    expect(success).to be(false)
  end

  it 'configures the public executable process before loading rush' do
    Tempfile.create(['rush-runtime-level', '.rb']) do |probe_file|
      probe_file.write(level_probe)
      probe_file.flush
      output, success = executable_probe(probe_file.path)

      expect([output, success]).to eq(['never', true])
    end
  end

  def probe(setting, source = probe_source)
    environment = { 'RUSH_RUNTIME_TYPECHECKS' => setting }
    stdout, stderr, status = Open3.capture3(environment, Gem.ruby, '-Ilib', '-e', source)
    [(stdout + stderr).strip, status.success?]
  end

  def executable_probe(probe_path)
    environment = { 'RUNTIME_LEVEL_PATH' => probe_path, 'RUBYOPT' => rubyopt(probe_path) }
    _stdout, _stderr, status = Open3.capture3(environment, Gem.ruby, 'exe/rush', '-c', ':')
    [File.read(probe_path), status.success?]
  end

  def rubyopt(probe_path)
    "#{ENV.fetch('RUBYOPT', nil)} -r#{probe_path}".strip
  end

  def level_probe
    <<~RUBY
      require 'sorbet-runtime'
      at_exit do
        level = T::Private::RuntimeLevels.instance_variable_get(:@default_checked_level)
        File.write(ENV.fetch('RUNTIME_LEVEL_PATH'), level.to_s)
      end
    RUBY
  end
end
