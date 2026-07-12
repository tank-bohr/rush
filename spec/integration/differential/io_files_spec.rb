# frozen_string_literal: true

# Differential cases that require stdin, sourced files, temp directories, PATH,
# persisted redirects, or other filesystem setup.
RSpec.describe 'rush vs dash (differential IO/files corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  # NB: snippets print values that may carry backslashes with printf '%s',
  # never echo — dash's echo expands XSI escapes (\t, \n, ...), so a backslash
  # in an echoed value would diverge on echo, not on read.
  read_corpus = [
    ['read a b c; echo "$a-$b-$c"', "x y z w\n"],
    ['read a b; echo "[$a][$b]"', "only\n"],
    ['read x; echo "rc=$?"', ''],
    ['read first rest; echo "$rest"', "one two three\n"],
    ['read x; printf "%s.rc=%s\n" "$x" "$?"', "a\\\nb\n"],
    ['read x; printf "%s\n" "$x"; read y; printf "%s\n" "$y"', "a\\\nb\nc\n"],
    ['read x; printf "%s.rc=%s\n" "$x" "$?"', 'a\\'],
    ['read x; printf "%s.rc=%s\n" "$x" "$?"', "a\\\n"],
    ['read x; printf "%s.rc=%s\n" "$x" "$?"', 'abc'],
    ['read x y; printf "<%s|%s>\n" "$x" "$y"', "a\\ b c\n"],
    ['read x; printf "%s\n" "$x"', "a\\\\b\n"],
    ['read x y; printf "<%s|%s>\n" "$x" "$y"', "a b \\ \n"],
    ['read x y; printf "<%s|%s>\n" "$x" "$y"', "a b c\\ \n"],
    ['read x y; printf "<%s|%s>\n" "$x" "$y"', "a b\\ \n"],
    ['read x y; printf "<%s|%s>\n" "$x" "$y"', "\\ a b\n"],
    ['read -r x y; printf "<%s|%s>\n" "$x" "$y"', "a\\ b c\n"],
    ['read -r -r x; printf "%s\n" "$x"', "a\\ b\n"],
    ['read -rr x; printf "%s\n" "$x"', "a\\ b\n"],
    ['read -- x; printf "%s\n" "$x"', "a\\ b\n"],
    ['read -rx; printf "rc=%s\n" "$?"', "unused\n"],
    ['read -r x; printf "%s\n" "$x"; read -r y; printf "%s\n" "$y"', "a\\\nb\n"],
    ['IFS=:; read x y; printf "<%s|%s>\n" "$x" "$y"', "a\\:b:c\n"],
    ['IFS=:; read x y; printf "<%s|%s>\n" "$x" "$y"', "a:b:\n"],
    ['IFS=:; read x y; printf "<%s|%s>\n" "$x" "$y"', "a:b:c:\n"],
    ['IFS=" :"; read x y; printf "<%s|%s>\n" "$x" "$y"', "a b  : \n"],
    ['IFS=" :"; read x y; printf "<%s|%s>\n" "$x" "$y"', "a \\\n: b\n"],
    ['IFS=; read x y; printf "<%s|%s>\n" "$x" "$y"', "a\\ b\n"],
    ['while read l; do echo "got $l"; done', "p\nq\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', "x:y:z\n"],
    ['IFS=:; read a b; echo "[$a][$b]"', "x:y:z\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', "x::z\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', ":x:\n"],
    ['IFS=" :"; read x y z; echo "[$x][$y][$z]"', "a :  b : c\n"]
  ].freeze

  read_corpus.each.with_index(1) do |(source, input), index|
    id = format('read-%03d', index)

    it "#{id}: matches dash for: #{source} <- #{input.inspect}" do
      expect(rush(source, input)).to eq(dash(source, input))
    end
  end

  fd_test_corpus = [
    '[ -c /dev/stdin ] </dev/null; echo $?',
    '[ -c /dev/stdout ] >/dev/null; echo $?',
    'echo x | { [ -p /dev/stdin ]; echo $?; }',
    'echo x | { [ -c /dev/stdin ] </dev/null; echo $?; }',
    'exec 3</dev/null; [ -c /dev/fd/3 ]; echo $?',
    '[ -e /dev/stdin ] <&-; echo $?',
    '[ ! -t 1 ] >&-; echo $?',
    '{ [ -c /dev/fd/5 ]; echo $?; } 5</dev/null'
  ].freeze

  fd_test_corpus.each do |source|
    it "matches dash for fd-facing test primary: #{source}" do
      expect(rush(source)).to eq(dash(source))
    end
  end

  it 'sources a file the same as dash' do
    Tempfile.create(['rush_src', '.sh']) do |file|
      file.write("greet() { echo \"hi $1\"; }\nVALUE=42\n")
      file.flush
      source = ". #{file.path}; greet world; echo $VALUE"
      expect(rush(source)).to eq(dash(source))
    end
  end

  it 'expands a pre-existing alias inside a sourced file like dash' do
    Tempfile.create(['rush_alias', '.sh']) do |file|
      file.write("g infile\n")
      file.flush
      source = "alias g=echo\n. #{file.path}"
      expect(rush(source)).to eq(dash(source))
    end
  end

  # A sourced file is read command by command too, so an alias it defines affects
  # its own later lines, and `return` is bounded to the script (it becomes the
  # `.` status, the caller continuing). A syntax error mid-file runs the earlier
  # commands then aborts the non-interactive shell with 2 (special-builtin error).
  dot_cases = {
    'alias defined in file affects a later line' => ["alias g=echo\ng hi\n", '. %s'],
    'return is bounded to the dot script' => ["echo in\nreturn 4\necho no\n",
                                              'f() { . %s; echo after=$?; }; f; echo end=$?'],
    'return at top level continues the caller' => ["echo in\nreturn 3\necho no\n", '. %s; echo end=$?'],
    'break propagates to an enclosing loop' => ["echo $i\nbreak\n",
                                                'for i in 1 2 3; do . %s; echo loop; done; echo done'],
    'syntax error mid-file runs the rest then aborts' => ["echo a\nbad )\necho c\n", '. %s; echo after'],
    'a syntax error inside a subshell aborts only it' => ["if\n", '( . %s ); echo after']
  }

  dot_cases.each do |label, (body, template)|
    it "sources incrementally like dash: #{label}" do
      Tempfile.create(['rush_dot', '.sh']) do |file|
        file.write(body)
        file.flush
        source = format(template, file.path)
        expect(rush(source)).to eq(dash(source))
      end
    end
  end

  # A redirect whose target cannot be opened leaves a regular command unrun with
  # status 2 and the shell carries on; on a special builtin it aborts the shell
  # (firing the EXIT trap) — `nodir/` does not exist, `.` is a directory.
  def redirect_failure_snippets
    ['echo x >nodir/f; echo AFTER', 'echo x >nodir/f; echo $?', 'cat <nodir/f; echo $?',
     'echo x >.; echo $?', 'echo x >>nodir/f; echo $?', '>nodir/f; echo $?',
     'read x <nodir/f; echo AFTER', 'f(){ echo in; }; f >nodir/f; echo AFTER',
     ': >nodir/f; echo AFTER', 'export X=1 >nodir/f; echo AFTER', 'eval : >nodir/f; echo AFTER',
     'exec 3>nodir/f; echo AFTER', 'trap "echo T" EXIT; : >nodir/f; echo AFTER',
     '( : >nodir/f ); echo AFTER', 'true; : >nodir/f; echo unreached']
  end

  it 'handles a failed redirect open the same as dash (status 2; fatal on a special builtin)' do
    Dir.mktmpdir do |dir|
      redirect_failure_snippets.each.with_index(1) do |snippet, index|
        id = format('redirect-failure-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  def input_redirect_snippets
    ['while read v; do echo "<$v>"; done < in', 'if read a; then echo "got $a"; fi < in',
     '{ read p; read q; echo "$p-$q"; } < in', 'for w in one; do echo "$w"; done < in']
  end

  it 'feeds an input redirect into a compound command the same as dash' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'in'), "x\ny\n")
      input_redirect_snippets.each.with_index(1) do |snippet, index|
        id = format('redirect-input-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  # A redirection's target is flushed+closed when the command finishes, so a
  # later command in the same invocation sees the data (the write file is opened
  # in sync mode, so a forked subshell's output survives its exit! too).
  def output_redirect_snippets
    ['echo x > f; cat f', '{ echo a; echo b; } > f; cat f', 'echo aaa > f; echo b > f; cat f',
     'echo a > f; echo b >> f; cat f', 'echo old > f; set -C; echo new > f; echo "rc=$?"; cat f',
     'echo old > f; set -C; echo force >| f; cat f', 'echo old > f; set -C; set +C; echo ok > f; cat f',
     'for i in 1 2 3; do echo $i; done > f; cat f',
     '( echo s1; echo s2 ) > f; cat f', '> f; cat f; echo "rc=$?"',
     'echo one > f; cat f; echo two > f; cat f', 'echo hi > f; read x < f; echo "[$x]"',
     '( for i in 1 2; do echo $i; done ) > f; wc -l < f', 'echo n > f; ( cat f; echo m ) > g; cat g',
     'echo a > f 2>&1; cat f', 'echo keep 2>&1 > f; cat f', '{ echo o; echo e >&2; } > f 2>&1; cat f',
     'ls /no_such_rush 2>f 1>&2; cat f']
  end

  it 'flushes a redirect target so a later command in the same shell sees it, like dash' do
    Dir.mktmpdir do |dir|
      output_redirect_snippets.each.with_index(1) do |snippet, index|
        id = format('redirect-output-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  def assignment_redirect_snippets
    ['echo $(echo err >&2) 2>f; printf "file=%s\n" "$(cat f 2>/dev/null)"',
     'X=$(echo err >&2) /bin/true 2>f; cat f; echo "x=$X"',
     'X=$(echo err >&2) 2>f; cat f; echo "x=$X"',
     '2>f X=$(echo err >&2); cat f; echo "x=$X"']
  end

  it 'applies same-command redirections to assignment command substitutions like dash' do
    Dir.mktmpdir do |dir|
      assignment_redirect_snippets.each.with_index(1) do |snippet, index|
        id = format('assignment-redirect-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  # Lowercase-only names keep byte-order sorting (rush) and LC_COLLATE sorting
  # (dash) in agreement, so these compare without forcing a locale.
  def glob_patterns
    ['echo *', 'echo *.txt', 'echo *.md', 'echo ?.txt', 'echo [ab].txt',
     'echo [!a].txt', 'echo [[:alpha:]].txt', 'echo [![:digit:]].txt',
     'echo file[[:digit:]]', 'echo sub/*', 'echo */*.txt', 'echo "*"', "echo '*'",
     'echo z*', 'set -f; echo *.txt', 'echo *.txt *.log', 'echo [a.txt',
     'echo a"*"', 'for f in *.txt; do echo "$f"; done', 'set -- *.txt; echo $#']
  end

  it 'expands pathname patterns the same as dash' do
    Dir.mktmpdir do |dir|
      %w[a.txt b.txt c.log file1 file2].each { |f| FileUtils.touch(File.join(dir, f)) }
      Dir.mkdir(File.join(dir, 'sub'))
      FileUtils.touch(File.join(dir, 'sub', 'x.txt'))
      glob_patterns.each.with_index(1) do |pattern, index|
        id = format('glob-%03d', index)
        source = "cd #{dir}; #{pattern}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{pattern}"
      end
    end
  end

  it 'keeps an escaped closing bracket inside a pathname class like dash' do
    Dir.mktmpdir do |dir|
      FileUtils.touch(File.join(dir, ']'))
      source = "cd #{dir}; echo [[:digit:]\\]]"
      expect(rush(source)).to eq(dash(source))
    end
  end

  # Redirect-only `exec` makes the redirection permanent for the rest of the
  # shell, unlike a per-command redirect: the opened target must stay open so
  # later commands keep writing to / reading from it. The dup form (2>&1) opens
  # nothing, so it already persisted; a forked subshell's exec must not leak out.
  def exec_persist_snippets
    ['exec 4>&1; exec > f; echo one; echo two; exec 1>&4 4>&-; cat f',
     'exec 3> f; echo hi >&3; exec 3>&-; cat f',
     'echo seed > f; exec 4>&1; exec >> f; echo more; exec 1>&4 4>&-; cat f',
     'printf "a\nb\n" > in; exec < in; read x; read y; echo "$x-$y"',
     'exec 2>&1; echo viastderr >&2', '( exec > sub; echo inside ); echo outside',
     'exec 4>&1; exec > f; echo first; exec > g; echo second; exec 1>&4 4>&-; cat f; cat g']
  end

  it 'makes redirect-only exec persist for the rest of the shell, like dash' do
    Dir.mktmpdir do |dir|
      exec_persist_snippets.each.with_index(1) do |snippet, index|
        id = format('exec-persist-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  # A function runs in the current shell, so a redirect on the *call* binds the
  # whole body (output, stderr dup, nested calls) and is torn down on return —
  # an `exec` inside `f >file` is scoped to that redirect (undone after f), but an
  # `exec` inside a call with no redirect persists (the body shares the shell io).
  def function_redirect_snippets
    ['f(){ echo body; }; f > f.txt; echo after; cat f.txt',
     'f(){ echo x; return 3; }; f > f.txt; echo "rc=$?"; cat f.txt',
     'f(){ echo out; echo err >&2; }; f > f.txt 2>&1; cat f.txt',
     'f(){ echo a; echo b; }; f > f.txt; f >> f.txt; cat f.txt',
     'f(){ echo outer; echo inner > i.txt; }; f > o.txt; printf "[o]"; cat o.txt; printf "[i]"; cat i.txt',
     'g(){ echo from-g; }; f(){ echo from-f; g; }; f > f.txt; cat f.txt',
     'exec 4>&1; f(){ exec > g.txt; }; f; echo A; exec 1>&4 4>&-; echo B; printf "G="; cat g.txt',
     'exec 4>&1; f(){ echo first; exec > o.txt; echo second; }; f > f.txt; echo A; exec 1>&4 4>&-; ' \
     'printf "F="; cat f.txt; printf "O="; cat o.txt']
  end

  it 'binds a redirect on a function call to the whole body, like dash' do
    Dir.mktmpdir do |dir|
      function_redirect_snippets.each.with_index(1) do |snippet, index|
        id = format('function-redirect-%03d', index)
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end

  # `hash name` resolves the name through PATH and remembers its full path; the
  # listing is sorted by name. Driven against a controlled PATH so rush and dash
  # resolve to identical paths regardless of the host.
  def hash_snippets
    ['hash z a; hash', 'hash a; hash z; hash', 'hash a; hash -r; hash',
     'hash a missing_zzz; echo "rc=$?"; hash']
  end

  it 'initializes $0 and positional parameters from -c operands like dash' do
    source = 'printf "%s:%s:%s:%s\n" "$0" "$1" "$2" "$#"'
    args = %w[name a b]
    expect(rush_with_args(source, args)).to eq(dash_with_args(source, args))
  end

  it 'caches and lists PATH command locations the same as dash' do
    Dir.mktmpdir do |dir|
      %w[a z].each do |name|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\n:\n")
        FileUtils.chmod(0o755, path)
      end
      hash_snippets.each.with_index(1) do |snippet, index|
        id = format('hash-path-%03d', index)
        source = "PATH=#{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "#{id} diverged on: #{snippet}"
      end
    end
  end
end
