# frozen_string_literal: true

# Alias substitution, eval, pipeline-stage, and fd-duplication cases.
RSpec.describe 'rush vs dash (differential alias/eval/pipeline/fd corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    # alias substitution happens at lex time and only affects *later* lines, so a
    # command-position name on a subsequent line is replaced by its value: a plain
    # command, a recursion-guarded self-reference, a nested chain, injected
    # reserved words, the trailing-<blank> argument chain, and never a quoted name,
    # a reserved word, an argument, or a case subject/pattern. Only stdout + exit
    # status are compared, so "not found" diagnostics on stderr are moot.
    "alias g=echo\ng hi",
    "alias g=echo\ng a b c",
    'alias g=echo; g hi',
    "alias echo='echo X'\necho hi",
    "alias a=echo\nalias b=a\nb two",
    "alias l='for i in 1 2'\nl\ndo echo $i; done",
    "alias first='echo '\nalias second=SECOND\nfirst second",
    "alias a='echo '\nalias b=hello\nalias c=world\na b c",
    "alias a='echo '\nalias b='B '\nalias c=CCC\na b c",
    "alias a='echo '\nalias b=hello\nalias hello=W\na b",
    "alias if=echo\nif hi",
    "alias x=echo\n\\x hi",
    "alias a=AAA\necho a",
    "alias a='echo '\nalias if=BAD\na if",
    "alias e=\ne echo hi",
    "alias p='echo hi | cat'\np",
    "alias greet='echo hello;'\ngreet world",
    "alias x=echo\ntrue && x A",
    "alias x=echo\nfalse | x B",
    "alias p=echo\ncase x in\n x) p ok;;\nesac",
    "alias r=BAD\ncase r in\n r) echo m;;\nesac",
    "alias p=echo\nfor n in 1 2; do p $n; done",
    "alias p=echo\nif true; then p hi; fi",
    "alias p=echo\n{ p hi; }",
    "alias p=echo\n( p hi )",
    "alias x=echo\ncommand x hi; echo rc=$?",
    # alias / unalias as builtins: listing (single-quoted name=value), querying,
    # removal, and type/command reporting. Multi-alias listings are sorted through
    # `sort` because rush sorts but dash lists in hash order.
    "alias ll=ls\nalias",
    "alias ll='ls -l'\nalias ll",
    "alias x=\"it's\"\nalias x",
    'alias',
    'alias nope; echo rc=$?',
    "alias a=1\nalias a=2\nalias a",
    "alias a=b=c\nalias a",
    "alias a=1\nalias b=2\nalias | sort",
    "alias a=1\nalias b=2\nunalias a\nalias",
    "alias a=1\nunalias -a\nalias",
    'unalias nope; echo rc=$?',
    'unalias; echo rc=$?',
    "alias ll='ls -l'\ntype ll",
    "alias ll='ls -l'\ncommand -v ll",
    "alias ll='ls -l'\ncommand -V ll",
    'type alias',
    # re-lexed input (eval, command substitution, a trap action) expands a
    # pre-existing alias, since the alias table is consulted wherever shell input
    # is tokenized.
    "alias g=echo\neval 'g hi'",
    "alias g=echo\neval g hi",
    "alias g=echo\necho \"$(g hi)\"",
    "alias g=echo\nx=$(g hi); echo $x",
    "alias g=echo\ntrap 'g bye' EXIT\necho body",
    # eval reads command by command (SourceRunner), so an alias or function it
    # defines shapes its own later lines. The result starts at success (empty/
    # comment-only input is 0) while $? stays live for the body;
    # break/continue/return/exit all propagate out.
    "eval 'alias e=echo\ne hi'",
    "eval 'g() {\necho hi\n}\ng'",
    "eval 'true\nfalse'; echo rc=$?",
    "false; eval ''; echo rc=$?",
    "false; eval '# c'; echo rc=$?",
    "eval 'false\n\n# c'; echo rc=$?",
    "false; eval 'echo $?'",
    "for i in 1 2 3; do eval 'echo $i\nbreak'; echo after; done; echo done",
    "for i in 1 2 3; do eval 'continue'; echo body $i; done; echo done",
    "f() { eval 'echo in\nreturn 5'; echo no; }; f; echo rc=$?",
    "eval 'echo a\nexit 7\necho b'; echo no",
    # a syntax error in eval is a special-builtin error: complete commands before
    # it run, then a non-interactive shell aborts with 2 (firing the EXIT trap);
    # a subshell aborts only itself.
    "eval 'echo a\nbad )'",
    "eval 'if'; echo after",
    "f() { eval 'if'; echo in; }; f; echo after",
    "trap 'echo bye' EXIT; eval 'if'; echo after",
    "( eval 'if' ); echo after",
    "eval 'echo a\nbad )'; echo after",
    # a pipeline stage may be any command, not only a simple command: a group,
    # subshell, if/while/for/case, or a function call, on either side of the `|`.
    '{ echo a; } | cat',
    'echo A | { echo G; cat; }',
    'echo Y | ( cat )',
    "printf '1\\n2\\n3\\n' | while read n; do echo \"got $n\"; done",
    'echo x | if cat; then echo T; fi',
    'echo z | case z in z) cat;; esac',
    'f() { cat; }; echo Y | f',
    'echo hi | { read x; echo \"[$x]\"; }',
    '{ echo a; echo b; } | wc -l',
    '( echo a; echo b ) | cat | cat',
    'echo a | cat | cat',
    # fd-duplication: n>&m / n<&m makes fd n a copy of fd m at that point in the
    # left-to-right fold; n>&- closes fd n (a write then fails, status 1); a fd
    # that is not open is status 2 and the shell continues; a non-numeric or
    # signed target is a special-builtin error that aborts with 2.
    'echo o; { echo e >&2; } 2>&1',
    'echo x 2>&1 | cat',
    '{ echo a; echo b >&2; } 2>&1 | cat',
    'echo x 3>&1',
    'echo close >&-; echo after',
    'echo close >&-; echo "rc=$?"',
    'echo ok 2>&-; echo "rc=$?"',
    'true >&9; echo "rc=$?"',
    'echo x >&9; echo AFTER',
    'echo a; echo x >&9; echo b',
    'read x <&-; echo "after=$?"',
    "cat <&0 <<E\nhi\nE",
    'echo x >&+1; echo AFTER',
    'echo x >&-1; echo AFTER',
    'read x <&+0; echo AFTER',
    'read x <&-1; echo AFTER',
    'echo x >&foo; echo AFTER',
    "trap 'echo bye' EXIT; echo x >&foo"
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('alias-eval-fd-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end
end
