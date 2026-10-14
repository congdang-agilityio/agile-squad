# Test helpers. Sourced by tests/*.test.sh through tests/run.sh.
# shellcheck shell=bash disable=SC2034
SQUAD="$(cd "$(dirname "${BASH_SOURCE[0]}")/../squad" && pwd)"
S="$SQUAD/scripts"
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"
PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" && pwd):$PATH"; export PATH
pass=0 fail=0
ok()  { echo "  ok    $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

# new_repo: a git repo with an origin (bare) and main pushed; prints its path
new_repo() {
  local d; d="$(mktemp -d)"
  git init -q --bare "$d/origin.git"
  git init -q -b main "$d/work"
  git -C "$d/work" config user.email test@example.com; git -C "$d/work" config user.name test
  git -C "$d/work" commit -q --allow-empty -m init
  git -C "$d/work" remote add origin "$d/origin.git"
  git -C "$d/work" push -q -u origin main
  echo "$d/work"
}
# squad_config <repo>: a minimal .squad/config.yml from the template with ids filled in
squad_config() {
  mkdir -p "$1/.squad"
  sed -e 's/^owner: OWNER/owner: acme/; s/^repo: REPO/repo: app/; s/^project_number: null/project_number: 7/' \
      "$SQUAD/templates/squad.config.yml" | sed 's/^  project_id: null/  project_id: "PVT_1"/' > "$1/.squad/config.yml"
}
