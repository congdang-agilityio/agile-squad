#!/usr/bin/env bash
# Compare models on the Team Lead's quick-lane decision (/squad:fix), dry run, read-only.
# Usage: tests/model-eval/quick-mode/run.sh <target repo clone> <out dir> [model ...]
# The cases in cases.tsv (id, expected fit|big, request) were written for the squad sandbox
# (a Next.js to-do app); adapt them to the target repository. Nothing is written to GitHub:
# the agent gets only Read, Grep and Glob. Then: score.sh <out dir>.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; plugin="$(cd "$here/../../../squad" && pwd)"
repo="$(cd "${1:?target repo}" && pwd)"; out="$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)"; shift 2
models=("$@"); ((${#models[@]})) || models=(sonnet opus)
one() { # one <model> <id> <request>
  local p="mode=quick request=\"$3\" priority=P2 config=.squad/config.yml
DRY RUN for an evaluation: do only step 1 of \"Mode quick\" (read the request and the code, decide). Create, edit or comment nothing on GitHub. Then end with the team-lead result block: status quick_planned (add the planned \"title\" and \"size\") or too_big_for_fix (with reason)."
  (cd "$repo" && timeout 900 claude -p --plugin-dir "$plugin" --agent squad:team-lead --model "$1" \
     --tools Read Grep Glob --add-dir "$plugin" --max-budget-usd 2 --output-format json "$p") > "$out/$1-$2.json"
}
export -f one; export repo plugin out
for m in "${models[@]}"; do while IFS=$'\t' read -r id _ req; do printf '%s\n%s\n%s\n' "$m" "$id" "$req"; done < "$here/cases.tsv"; done \
  | xargs -d '\n' -n 3 -P 4 bash -c 'one "$0" "$1" "$2"'
