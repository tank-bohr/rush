#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
regex_bytes=$(bundle exec ruby -I"$root/lib" -e \
  'require "sorbet-runtime"; require "rush/system_calls/regex_abi"; print Rush::SystemCalls::RegexAbi::REGEX_BYTES')
probe=${TMPDIR:-/tmp}/rush-regex-abi-$$
trap 'rm -f "$probe" "$probe.c"' EXIT HUP INT TERM

cat > "$probe.c" <<'C'
#include <stddef.h>
#include <stdio.h>
#include <regex.h>
#include <gnu/libc-version.h>

#ifndef REGEX_BYTES
# error "REGEX_BYTES must come from Rush::SystemCalls::RegexAbi"
#endif

_Static_assert(sizeof(regex_t) <= REGEX_BYTES,
               "regex_t exceeds Rush::SystemCalls::RegexAbi::REGEX_BYTES");
_Static_assert(_Alignof(regex_t) <= _Alignof(max_align_t),
               "regex_t requires stronger alignment than malloc provides");

int main(void)
{
  printf("rush regex ABI smoke ok: glibc %s, sizeof(regex_t)=%zu, align=%zu, buffer=%d\n",
         gnu_get_libc_version(), sizeof(regex_t), _Alignof(regex_t), REGEX_BYTES);
  return 0;
}
C

"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -DREGEX_BYTES="$regex_bytes" "$probe.c" -o "$probe"
"$probe"
