#!/usr/bin/env bash
# Shared helpers for squad scripts. Source it; do not execute it.
# shellcheck disable=SC2034  # variables here are used by the scripts that source this file
# Requires: bash 4+, gh, jq, awk, git.

if ((BASH_VERSINFO[0] < 4)); then
  echo "error: squad scripts need bash 4 or newer (macOS: brew install bash)" >&2; exit 1
fi

# errexit must also apply inside $(...) so a failing helper stops the script
shopt -s inherit_errexit 2>/dev/null || true

SQUAD_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQUAD_ROOT="$(dirname "$SQUAD_SCRIPTS")"

STATUSES=("Backlog" "Todo" "In Progress" "In Review" "QA" "Done" "Released")
PRIORITIES=(P0 P1 P2 P3)
SIZES=(XS S M)
ISSUE_TYPES=(epic story task bug report)

die()  { echo "error: $*" >&2; exit "${EXIT_CODE:-1}"; }
warn() { echo "warning: $*" >&2; }
info() { echo "$*" >&2; }

need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' is required but not installed"
  done
}

in_list() { # in_list <value> <items...>
  local v="$1" x; shift
  for x in "$@"; do [[ "$x" == "$v" ]] && return 0; done
  return 1
}

# ---------------------------------------------------------------- config

# Config path: $SQUAD_CONFIG, else .squad/config.yml in the MAIN worktree
# (so scripts behave the same when run from .worktrees/<issue>).
config_path() {
  if [[ -n "${SQUAD_CONFIG:-}" ]]; then echo "$SQUAD_CONFIG"; return; fi
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || die "not inside a git repository (or set SQUAD_CONFIG)"
  echo "$(dirname "$common")/.squad/config.yml"
}

# Convert the YAML subset used by squad configs to JSON.
# Supports: nested block maps, block lists of scalars, flow maps {a: 1},
# flow lists [a, "b"], quoted/unquoted scalars, comments.
yaml_to_json() {
  awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function strip_comment(s,   i, c, q, out) {
    q = ""; out = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "" && (c == "\"" || c == "\x27")) q = c
      else if (q != "" && c == q) q = ""
      else if (q == "" && c == "#" && (i == 1 || substr(s, i-1, 1) ~ /[ \t]/)) break
      out = out c
    }
    return out
  }
  function jstr(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s)
    return "\"" s "\""
  }
  function scalar(s,   q) {
    s = trim(s)
    if (s == "" || s == "~" || s == "null") return "null"
    q = substr(s, 1, 1)
    if ((q == "\"" || q == "\x27") && substr(s, length(s), 1) == q) {
      s = substr(s, 2, length(s) - 2)
      if (q == "\x27") gsub(/\x27\x27/, "\x27", s)
      else { gsub(/\\"/, "\"", s) }
      return jstr(s)
    }
    if (s ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/) return s
    if (s == "true" || s == "false") return s
    return jstr(s)
  }
  # split flow content on top-level commas (outside quotes) into parts[]
  function fsplit(s, parts,   i, c, q, cur, n) {
    n = 0; q = ""; cur = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "" && (c == "\"" || c == "\x27")) q = c
      else if (q != "" && c == q) q = ""
      if (q == "" && c == ",") { parts[++n] = cur; cur = ""; continue }
      cur = cur c
    }
    if (trim(cur) != "") parts[++n] = cur
    return n
  }
  function keyof(s) {
    s = trim(s)
    if (s ~ /^".*"$/ || s ~ /^\x27.*\x27$/) s = substr(s, 2, length(s) - 2)
    return jstr(s)
  }
  # position of the key/value colon (": " or trailing ":") outside quotes
  function colon(s,   i, c, q) {
    q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "" && (c == "\"" || c == "\x27")) q = c
      else if (q != "" && c == q) q = ""
      else if (q == "" && c == ":" && (i == length(s) || substr(s, i+1, 1) == " ")) return i
    }
    return 0
  }
  function flow(s,   parts, n, i, out, p) {
    s = trim(s)
    if (substr(s, 1, 1) == "[") {
      n = fsplit(substr(s, 2, length(s) - 2), parts); out = ""
      for (i = 1; i <= n; i++) out = out (i > 1 ? "," : "") scalar(parts[i])
      return "[" out "]"
    }
    n = fsplit(substr(s, 2, length(s) - 2), parts); out = ""
    for (i = 1; i <= n; i++) {
      p = colon(parts[i]); if (!p) { err = "bad flow map entry: " parts[i]; return "null" }
      out = out (i > 1 ? "," : "") keyof(substr(parts[i], 1, p - 1)) ":" scalar(substr(parts[i], p + 1))
    }
    return "{" out "}"
  }
  function value(rest) {
    rest = trim(rest)
    if (rest ~ /^[\[{]/) return flow(rest)
    return scalar(rest)
  }
  # parse lines starting at i with indentation ind; sets global NXT
  function block(i, ind,   out, n, p, k, rest, v) {
    out = ""; n = 0
    if (txt[i] ~ /^-( |$)/) {
      while (i <= N && ind_[i] == ind && txt[i] ~ /^-( |$)/) {
        out = out (n++ ? "," : "") value(substr(txt[i], 2)); i++
      }
      NXT = i; return "[" out "]"
    }
    while (i <= N && ind_[i] == ind) {
      p = colon(txt[i])
      if (!p) { err = "line " ln[i] ": expected key: value"; NXT = N + 1; return "null" }
      k = keyof(substr(txt[i], 1, p - 1)); rest = trim(substr(txt[i], p + 1)); i++
      if (rest != "") v = value(rest)
      else if (i <= N && ind_[i] > ind) { v = block(i, ind_[i]); i = NXT }
      else if (i <= N && ind_[i] == ind && txt[i] ~ /^-( |$)/) { v = block(i, ind); i = NXT }
      else v = "null"
      out = out (n++ ? "," : "") k ":" v
    }
    if (i <= N && ind_[i] > ind) { err = "line " ln[i] ": unexpected indentation" }
    NXT = i; return "{" out "}"
  }
  {
    line = strip_comment($0); sub(/[ \t\r]+$/, "", line)
    if (line ~ /^[ \t]*$/ || line == "---") next
    match(line, /^ */)
    N++; ind_[N] = RLENGTH; txt[N] = substr(line, RLENGTH + 1); ln[N] = NR
  }
  END {
    if (N == 0) { print "{}"; exit 0 }
    out = block(1, ind_[1])
    if (err != "") { print "yaml: " err > "/dev/stderr"; exit 3 }
    print out
  }' "$1"
}

CFG_JSON=""
load_config() {
  local path; path="$(config_path)"
  [[ -f "$path" ]] || die "config not found: $path (run the squad setup skill first)"
  CFG_JSON="$(yaml_to_json "$path")" || die "cannot parse $path"
  jq -e . >/dev/null <<<"$CFG_JSON" || die "config parsed to invalid JSON: $path"
}

# cfg <jq-path> : print a config value ("" if missing)
# (false is printed as "false"; only null/missing print nothing)
cfg() { jq -r "($1) as \$v | if \$v == null then empty elif (\$v | type) == \"object\" or (\$v | type) == \"array\" then (\$v | tojson) else \$v end" <<<"$CFG_JSON"; }

# cfg_req <jq-path> : like cfg but fails when missing
cfg_req() {
  local v; v="$(cfg "$1")"
  [[ -n "$v" ]] || die "config value $1 is missing in $(config_path) (re-run setup?)"
  echo "$v"
}

# ---------------------------------------------------------------- github

OWNER="" REPO="" PROJECT_NUMBER="" PROJECT_ID=""
load_project() {
  load_config
  OWNER="$(cfg_req .owner)"; REPO="$(cfg_req .repo)"
  PROJECT_NUMBER="$(cfg_req .project_number)"; PROJECT_ID="$(cfg_req .ids.project_id)"
}

# gql <query> [gh api args...] : run a GraphQL query, fail on errors
gql() {
  local q="$1"; shift
  local out
  out="$(gh api graphql -f query="$q" "$@" 2>&1)" || die "GraphQL request failed: $out"
  if jq -e '.errors? | length > 0' >/dev/null 2>&1 <<<"$out"; then
    die "GraphQL error: $(jq -r '[.errors[].message] | join("; ")' <<<"$out")"
  fi
  echo "$out"
}

issue_args() { # issue_args "#12,#13" 14 ... : one issue number per line (accepts #, commas, spaces)
  local a
  for a in "$@"; do tr ', ' '\n\n' <<<"$a"; done | sed 's/^#//' | grep -E '^[0-9]+$' || true
}

issue_node_id() { # issue_node_id <number>
  gql 'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id}}}' \
    -F o="$OWNER" -F r="$REPO" -F n="$1" | jq -r '.data.repository.issue.id // empty'
}

# Print usage from the header comment block of the calling script.
usage_from() { sed -n '/^# Usage:/,/^[^#]/{/^[^#]/d;s/^# \{0,1\}//;p;}' "$1"; }
