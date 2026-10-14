#!/usr/bin/env bash
# Run every tests/*.test.sh (or the ones given) and print a summary. Exit 1 on any failure.
# Usage: tests/run.sh [tests/name.test.sh ...]
set -uo pipefail
cd "$(dirname "$0")" || exit 1
files=("$@"); ((${#files[@]})) || files=(*.test.sh)
total_pass=0 total_fail=0
for f in "${files[@]}"; do
  echo "== ${f##*/}"
  out="$(bash -c 'source ./lib.sh; source "$1"; echo "__RESULT $pass $fail"' _ "$f" 2>&1)"
  grep -v '^__RESULT' <<<"$out"
  read -r _ p fl < <(grep '^__RESULT' <<<"$out" || echo "__RESULT 0 1")
  total_pass=$((total_pass + p)); total_fail=$((total_fail + fl))
done
echo "== $total_pass passed, $total_fail failed"
((total_fail == 0))
