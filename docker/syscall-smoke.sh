#!/usr/bin/env sh
set -eu

SOURCE='
before=$(ulimit -Sn)
ulimit -Sn 64
printf "before=%s\nsoft=%s\nhard=%s\n" "$before" "$(ulimit -Sn)" "$(ulimit -Hn)"
'

if ! output=$(bundle exec ruby -Ilib exe/rush -c "$SOURCE" 2>&1); then
  printf 'rush ulimit smoke failed:\n%s\n' "$output" >&2
  exit 1
fi

before=
soft=
hard=
for line in $output; do
  case $line in
    before=*) before=${line#before=} ;;
    soft=*) soft=${line#soft=} ;;
    hard=*) hard=${line#hard=} ;;
  esac
done

fail() {
  printf '%s\nrush output:\n%s\n' "$1" "$output" >&2
  exit 1
}

[ -n "$before" ] || fail 'rush ulimit smoke did not report the initial soft limit'
[ "$soft" = 64 ] || fail 'rush ulimit smoke did not lower RLIMIT_NOFILE soft limit to 64'
[ "$hard" -ge 64 ] 2>/dev/null || fail 'rush ulimit smoke reported an invalid hard limit'

printf 'rush Docker syscall smoke ok: nofile soft %s -> %s (hard %s)\n' "$before" "$soft" "$hard"
