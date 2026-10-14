#!/usr/bin/env bash
# Score run.sh output: right decision, a fenced JSON result block, an English title, cost.
# Usage: tests/model-eval/quick-mode/score.sh <out dir>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; out="${1:?out dir}"
for m in $(ls "$out" | sed -n 's/-[A-Z][0-9]*\.json$//p' | sort -u); do
  dec=0 json=0 eng=0 n=0
  while IFS=$'\t' read -r id exp _; do
    f="$out/$m-$id.json"; [[ -s "$f" ]] || continue; n=$((n + 1)); r="$(jq -r .result "$f")"
    st="$(grep -oE 'quick_planned|too_big_for_fix' <<<"$r" | tail -1 || true)"
    [[ ( $exp == fit && $st == quick_planned ) || ( $exp == big && $st == too_big_for_fix ) ]] && dec=$((dec + 1))
    grep -q '```json' <<<"$r" && grep -qE '"role" *: *"team-lead"' <<<"$r" && json=$((json + 1))
    t="$(grep -oE '"title" *: *"[^"]*"' <<<"$r" | tail -1 || true)"
    LC_ALL=C grep -q '[^ -~]' <<<"${t//·/}" || eng=$((eng + 1))
  done < "$here/cases.tsv"
  printf '%-7s decisions %d/%d  json block %d/%d  english title %d/%d  cost $%s\n' "$m" $dec $n $json $n $eng $n \
    "$(jq -s 'map(.total_cost_usd) | add * 100 | round / 100' "$out"/"$m"-*.json)"
done
