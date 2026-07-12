# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# A tailored glibc locale is the only honest way to exercise the LC_COLLATE
# semantics Ruby does not expose. dash 0.5.13.4 misses these three bracket
# forms, so this is a documented standard-over-oracle test, not differential.
RSpec.describe 'locale-complete shell patterns' do
  def project_root
    File.expand_path('../..', __dir__)
  end

  def build_locale(directory)
    system('localedef', '-i', 'cs_CZ', '-f', 'UTF-8', "#{directory}/cs_TEST.UTF-8",
           out: File::NULL, err: File::NULL)
  end

  it 'matches and sorts with a tailored locale across case, removal and pathname expansion' do
    skip 'glibc collation backend unavailable' unless Rush::SystemCalls::COLLATION.available?
    expect(system('command -v localedef >/dev/null')).to be(true)

    Dir.mktmpdir('rush-locale') do |locale_dir|
      expect(build_locale(locale_dir)).to be(true)
      Dir.mktmpdir('rush-locale-files') { |work| expect(run_probe(locale_dir, work)).to eq(expected_output) }
    end
  end

  def run_probe(locale_dir, work)
    %w[a á h ch i].each { |name| File.write("#{work}/#{name}", '') }
    %w[paths/a/b paths/one/two].each { |path| FileUtils.mkdir_p("#{work}/#{path}") }
    %w[paths/a/x paths/a/b/x paths/one/x paths/one/two/x paths/{a,b}x].each do |path|
      File.write("#{work}/#{path}", '')
    end
    source = <<~'SH'
      LC_ALL=C
      case ch in [[.ch.]]) echo wrong-locale;; esac
      LC_ALL=cs_TEST.UTF-8
      case ch in [[.ch.]]) echo collating;; esac
      case á in [[=a=]]) echo equivalent;; esac
      case á in [a-c]) echo range;; esac
      v=chX; echo "${v#[[.ch.]]}"
      printf '<%s>\n' [[.ch.]]
      printf 'all:%s\n' *
      printf 'stars:%s\n' paths/**/x
      printf 'wide:%s\n' paths/[a]*/x
      printf 'brace:%s\n' paths/{a,b}*
    SH
    env = { 'BUNDLE_GEMFILE' => "#{project_root}/Gemfile", 'LOCPATH' => locale_dir, 'LC_ALL' => 'cs_TEST.UTF-8' }
    out, _err, status = Open3.capture3(env, RbConfig.ruby, "-I#{project_root}/lib", "#{project_root}/exe/rush",
                                       '-c', source, chdir: work)
    [out, status.exitstatus]
  end

  def expected_output
    text = "collating\nequivalent\nrange\nX\n<ch>\n"
    text += "all:a\nall:á\nall:h\nall:ch\nall:i\nall:paths\n"
    text += "stars:paths/a/x\nstars:paths/one/x\nwide:paths/a/x\nbrace:paths/{a,b}x\n"
    [text, 0]
  end
end
