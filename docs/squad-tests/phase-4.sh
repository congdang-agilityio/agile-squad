#!/usr/bin/env bash
# Phase 4 script tests: pr-size.sh against PRs and a branch on the sandbox.
# Usage: cd <sandbox clone> && bash phase-4.sh <path>/squad/scripts
set -uo pipefail
S="${1:?usage: phase-4.sh <squad/scripts dir>}"
pass=0 fail=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass + 1)); else echo "FAIL  $1"; fail=$((fail + 1)); fi; }

J="$("$S/pr-size.sh" 111 --size XS)"; rc=$?
check "pr-size: small PR (#111, 15 lines, 2 files) is within XS, exit 0" \
  '[[ $rc == 0 ]] && jq -e ".over == false and .lines == 15 and .files == 2" <<<"$J" >/dev/null'
J="$("$S/pr-size.sh" 66 --size XS)"; rc=$?
check "pr-size: large docs PR (#66) is over XS, exit 3" '[[ $rc == 3 ]] && jq -e .over <<<"$J" >/dev/null'
J="$("$S/pr-size.sh" 120)"; rc=$?
check "pr-size: size read from the linked task (#117 = S); test files excluded" \
  '[[ $rc == 0 ]] && jq -e ".size == \"S\" and (.excluded | any(test(\"\\\\.test\\\\.ts$\")))" <<<"$J" >/dev/null'
J="$("$S/pr-size.sh" 121 --size XS)"; rc=$?
check "pr-size: oversized XS PR (#121, 73 lines) is over, exit 3" '[[ $rc == 3 ]] && jq -e ".lines > 50" <<<"$J" >/dev/null'
git fetch --quiet origin feat/118-add-http-status-reason-phrases-in-vietna 2>/dev/null
J="$("$S/pr-size.sh" origin/feat/118-add-http-status-reason-phrases-in-vietna --size S)"; rc=$?
check "pr-size: branch mode counts against origin/main (73 lines within S)" \
  '[[ $rc == 0 ]] && jq -e ".lines == 73 and .files == 1" <<<"$J" >/dev/null'
check "pr-size: unknown size is an error" '! "$S/pr-size.sh" 111 --size L >/dev/null 2>&1'

echo "----"; echo "passed $pass, failed $fail"
[[ "$fail" == 0 ]]
