# frozen_string_literal: true

RSpec.describe Rush::ErrorPolicy do
  let(:contexts) { described_class::CONTEXTS }

  it 'covers every named Rush::Error class with every runtime context' do
    error_classes = Rush.constants.filter_map do |name|
      value = Rush.const_get(name)
      value if value.is_a?(Class) && value <= Rush::Error
    end
    expect(described_class::MATRIX.keys).to match_array(error_classes)
    expect(described_class::MATRIX.values.map(&:keys)).to all(match_array(contexts))
  end

  it 'classifies operational failures by boundary' do
    classes = [Rush::ParseError, Rush::IncompleteInput, Rush::ExpansionError, Rush::ReadonlyError]
    expect(classes.map { |klass| described_class::MATRIX.fetch(klass) })
      .to all(eq(batch: :abort2, interactive: :recover2, subshell: :abort2,
                 command: :demote2, signal_trap: :ignore, exit_trap: :abort2))
  end

  it 'keeps special-builtin errors visible in ordinary traps' do
    expect(described_class::MATRIX.fetch(Rush::BuiltinError))
      .to eq(batch: :abort2, interactive: :recover2, subshell: :abort2,
             command: :demote2, signal_trap: :propagate, exit_trap: :abort2)
  end

  it 'leaves errors with narrower owners visible except at a child top level' do
    classes = [Rush::Error, Rush::InvocationError, Rush::TestError, Rush::RedirectError, Rush::JobError]
    expect(classes.map { |klass| described_class::MATRIX.fetch(klass) })
      .to all(eq(batch: :propagate, interactive: :propagate, subshell: :abort2,
                 command: :propagate, signal_trap: :propagate, exit_trap: :propagate))
  end

  it 'classifies interrupt and control-flow signals without accidental demotion' do
    expected = {
      Rush::Interrupted => %i[interrupt130 recover130 abort2 propagate propagate propagate],
      Rush::ExitSignal => %i[propagate propagate return_code propagate propagate override_code],
      Rush::ReturnSignal => %i[propagate ignore return_code propagate ignore preserve_code],
      Rush::LoopControl => %i[propagate propagate last_status propagate ignore preserve_code],
      Rush::BreakSignal => %i[propagate propagate last_status propagate ignore preserve_code],
      Rush::ContinueSignal => %i[propagate propagate last_status propagate ignore preserve_code]
    }
    expected.each do |klass, decisions|
      expect(contexts.map { |context| described_class.decision(context, error(klass)) }).to eq(decisions)
    end
    control = expected.except(Rush::Interrupted).values.flatten
    expect(control & described_class::DIAGNOSTIC_DECISIONS).to be_empty
  end

  def error(klass)
    return klass.new(1) if klass <= Rush::LoopControl || [Rush::ExitSignal, Rush::ReturnSignal].include?(klass)

    klass.new('error')
  end
end
