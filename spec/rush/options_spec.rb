# frozen_string_literal: true

RSpec.describe Rush::Options do
  subject(:options) { described_class.new }

  it 'accepts every toggleable long name in the listing vocabulary' do
    expect(described_class::NAMES.values).to include(*described_class::LONG.values, :interactive, :stdin)
  end

  describe '#settings_rows' do
    it 'renders every option off, in dash order and column format, by default' do
      expect(options.settings_rows).to eq(
        ['errexit         off', 'noglob          off', 'interactive     off',
         'monitor         off', 'noexec          off', 'stdin           off', 'xtrace          off',
         'verbose         off', 'noclobber       off', 'allexport       off',
         'nounset         off', 'pipefail        off']
      )
    end

    it 'flips a row to on when the option is enabled' do
      options.set(:errexit, true)
      expect(options.settings_rows).to include('errexit         on')
    end
  end

  describe '#reinput_lines' do
    it 'renders a set +o line for an option that is off' do
      expect(options.reinput_lines).to include('set +o pipefail')
    end

    it 'renders a set -o line for an enabled option' do
      options.set(:monitor, true)
      expect(options.reinput_lines).to include('set -o monitor')
    end

    it 'covers the same names as the settings table, in the same order' do
      names = options.reinput_lines.map { |line| line.split.last }
      expect(names).to eq(options.settings_rows.map { |row| row.split.first })
    end
  end
end
