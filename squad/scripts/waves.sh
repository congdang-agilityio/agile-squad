#!/usr/bin/env bash
# waves.sh: group tasks into parallel waves (board-conventions §7) and write the Wave field.
#
# Usage:
#   waves.sh plan <issue>... [--start N] [--write]
#   waves.sh plan --from-json <file> [--start N] [--max-parallel N]   (offline, for tests)
#
# Reads each task body (task-template.md): "Depends on" line, "Files (expected)" section,
# "Layer" and "Serial" lines. Rules:
#   - a task's wave is after every dependency in the set; a dependency outside the set must be
#     Done/Released or already have an earlier Wave (otherwise it is reported in "unplanned_deps")
#   - tasks in one wave never share a file (a path, or a directory/glob prefix of another)
#   - serial tasks are alone in their wave: Serial: yes, Layer schema/config/infra, or files
#     such as migrations, package manifests, lockfiles, CI config, shared routing/config
#   - at most parallel.max_parallel_dev tasks per wave
# Scheduling: wave by wave; ready tasks ranked by critical path (longest chain of dependent
# tasks), then priority (P0 first), then issue number; a serial task gets a wave of its own.
# --start: first wave number (default: 1 + the highest Wave of open, not Done/Released items
# outside the set). --write sets the Wave field on the board.
# Output JSON: {first_wave, waves, wave_of, serial, serial_reasons, unplanned_deps, warnings}.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOARD="$SQUAD_SCRIPTS/board.sh"

PY='
import json, re, sys
tasks, start, cap = json.load(open(sys.argv[1])), int(sys.argv[2]), int(sys.argv[3])
outside = json.load(open(sys.argv[4]))     # {number: {"status":..,"wave":..}} for deps not in set

SERIAL_LAYERS = {"schema", "migration", "config", "infra", "ci", "dependencies", "deps", "build"}
SERIAL_FILES = [r"(^|/)migrations?/", r"(^|/)prisma/schema\.prisma$", r"\.sql$", r"(^|/)schema\.(rb|sql|prisma)$",
    r"(^|/)package\.json$", r"(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?)$",
    r"(^|/)(requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|Gemfile(\.lock)?|go\.(mod|sum)|Cargo\.(toml|lock))$",
    r"^\.github/", r"(^|/)Dockerfile$", r"(^|/)docker-compose[^/]*$", r"(^|/)railway\.(json|toml)$",
    r"(^|/)(tsconfig|vite\.config|next\.config|webpack\.config|eslint\.config|jest\.config|vitest\.config)[^/]*$",
    r"(^|/)\.env(\.example)?$", r"(^|/)(routes|router)\.(ts|js|tsx|jsx|py|rb)$", r"(^|/)app\.(ts|js)$",
    r"(^|/)middleware\.(ts|js)$"]

def section(body, name):
    m = re.search(r"^#{2,3}\s*" + re.escape(name) + r".*?$(.*?)(?=^#{1,3}\s|\Z)", body, re.M | re.S | re.I)
    return m.group(1) if m else ""

def field(body, name):
    m = re.search(r"^\s*[-*]?\s*\**" + name + r"\**\s*:?\**\s*:?\s*(.*)$", body, re.M | re.I)
    return m.group(1).strip() if m else ""

def files_of(body):
    out = []
    for line in section(body, "Files (expected)").splitlines():
        line = line.strip()
        if not line.startswith(("-", "*")):
            continue
        m = re.search(r"`([^`]+)`", line)
        p = m.group(1) if m else line.lstrip("-* ").split()[0] if line.lstrip("-* ") else ""
        p = p.strip()
        p = p[2:] if p.startswith("./") else p
        if p:
            out.append(p)
    return out

def prefix(p):   # globs and directories become prefixes
    p = p.split("*")[0]
    return p

def overlap(a, b):
    pa, pb = prefix(a), prefix(b)
    if a == b:
        return True
    da, db = ("*" in a or a.endswith("/")), ("*" in b or b.endswith("/"))
    return (da and b.startswith(pa)) or (db and a.startswith(pb))

info, warnings = {}, []
for t in tasks:
    n, body = t["number"], t.get("body") or ""
    deps = sorted({int(x) for line in body.splitlines() if re.search(r"depends on", line, re.I)
                   for x in re.findall(r"#(\d+)", line)} - {n})
    files = files_of(body)
    if not files:
        warnings.append(f"#{n} has no Files (expected) entries; it is treated as serial")
    layer = field(body, "Layer").split()[0].strip("`*.,").lower() if field(body, "Layer") else ""
    serial_line = field(body, "Serial").lower()
    reason = ""
    if serial_line.startswith("yes"):
        reason = "marked Serial: " + field(body, "Serial")
    elif layer in SERIAL_LAYERS:
        reason = f"layer {layer}"
    elif not files:
        reason = "no Files (expected)"
    else:
        for f in files:
            if any(re.search(rx, f) for rx in SERIAL_FILES):
                reason = f"touches shared file {f}"
                break
    info[n] = {"deps": deps, "files": files, "serial": reason,
               "prio": (t.get("priority") or "P9"), "status": t.get("status")}

nums = set(info)
unplanned, wave_floor = {}, {}
for n, i in info.items():
    floor = start
    for d in i["deps"]:
        if d in nums:
            continue
        o = outside.get(str(d)) or {}
        if o.get("status") in ("Done", "Released"):
            continue
        if o.get("wave") is not None and int(o["wave"]) < start:
            continue
        if o.get("wave") is not None:
            floor = max(floor, int(o["wave"]) + 1)
            continue
        unplanned.setdefault(str(n), []).append(d)
    wave_floor[n] = floor

# list scheduling, wave by wave: rank ready tasks by critical path (longest chain of tasks
# that depend on them), then priority, then number; a serial task gets a wave of its own,
# otherwise the wave is filled with ready, non-serial, non-overlapping tasks up to the cap.
dependents = {n: [m for m in nums if n in info[m]["deps"]] for n in nums}
cp, visiting = {}, set()
def chain(n):
    if n in cp:
        return cp[n]
    if n in visiting:
        sys.exit("error: dependency cycle involving #%d" % n)
    visiting.add(n)
    cp[n] = 1 + max([chain(m) for m in dependents[n]] or [0])
    visiting.discard(n)
    return cp[n]
for n in nums:
    chain(n)
rank = lambda n: (-cp[n], info[n]["prio"], n)

wave_of, members, left, w = {}, {}, set(nums), start
while left:
    ready = sorted([n for n in left if wave_floor[n] <= w and
                    all(d not in nums or (d in wave_of and wave_of[d] < w) for d in info[n]["deps"])], key=rank)
    if not ready:          # only waiting for a dependency floor outside the set (cycles exited above)
        w += 1
        continue
    if info[ready[0]]["serial"]:
        pick = [ready[0]]
    else:
        pick = []
        for n in ready:
            if len(pick) >= cap:
                break
            if info[n]["serial"]:
                continue
            if any(overlap(a, b) for x in pick for a in info[n]["files"] for b in info[x]["files"]):
                continue
            pick.append(n)
    for n in pick:
        wave_of[n] = w
        left.discard(n)
    members[w] = pick
    w += 1

first = min(members) if members else start
last = max(members) if members else start - 1
waves = [sorted(members.get(w, []), key=lambda n: (info[n]["prio"], n)) for w in range(first, last + 1)]
print(json.dumps({
    "first_wave": first,
    "waves": waves,
    "wave_of": {str(n): w for n, w in sorted(wave_of.items())},
    "serial": sorted(n for n in nums if info[n]["serial"]),
    "serial_reasons": {str(n): info[n]["serial"] for n in sorted(nums) if info[n]["serial"]},
    "files": {str(n): info[n]["files"] for n in sorted(nums)},
    "unplanned_deps": unplanned,
    "warnings": warnings}, indent=1))
'

cmd_plan() {
  local from="" start="" write=0 cap="" nums=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from-json) from="${2:?}"; shift 2 ;;
      --start) start="${2:?}"; shift 2 ;;
      --max-parallel) cap="${2:?}"; shift 2 ;;
      --write) write=1; shift ;;
      [0-9]*) nums+=("$1"); shift ;;
      *) die "unknown argument $1" ;;
    esac
  done
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  if [[ -n "$from" ]]; then
    [[ "$write" == 0 ]] || die "--write cannot be used with --from-json"
    cp "$from" "$tmp/tasks.json"; echo '{}' > "$tmp/outside.json"
    start="${start:-1}"; cap="${cap:-2}"
  else
    [[ ${#nums[@]} -gt 0 ]] || die "usage: waves.sh plan <issue>... [--start N] [--write]"
    load_project
    cap="${cap:-$(cfg '.parallel.max_parallel_dev')}"; cap="${cap:-2}"
    local board n it arr='[]'
    board="$("$BOARD" list all)"
    for n in "${nums[@]}"; do
      it="$("$BOARD" get "$n")" || die "#$n is not on the board"
      arr="$(jq -c --argjson it "$it" --argjson n "$n" \
              --arg body "$(gh issue view "$n" --repo "$OWNER/$REPO" --json body -q .body)" \
              '. + [$it + {number:$n, body:$body}]' <<<"$arr")"
    done
    echo "$arr" > "$tmp/tasks.json"
    # dependencies outside the set: status and wave (direct lookup when not in the listing)
    local deps d st out='{}'
    deps="$(jq -r --argjson set "$(printf '%s\n' "${nums[@]}" | jq -s .)" '
      [.[].body | split("\n")[] | select(test("depends on"; "i")) | scan("#([0-9]+)")[0] | tonumber]
      | unique - $set | .[]' "$tmp/tasks.json")"
    for d in $deps; do
      st="$(jq -c --argjson d "$d" '[.[] | select(.number == $d) | {status, wave}] | first // empty' <<<"$board")"
      [[ -n "$st" ]] || st="$("$BOARD" get "$d" 2>/dev/null | jq -c '{status, wave}')" || st='{}'
      [[ -n "$st" ]] || st='{}'
      out="$(jq -c --arg k "$d" --argjson v "$st" '. + {($k): $v}' <<<"$out")"
    done
    echo "$out" > "$tmp/outside.json"
    if [[ -z "$start" ]]; then
      start="$(jq --argjson set "$(printf '%s\n' "${nums[@]}" | jq -s .)" '
        [.[] | select((.number as $n | $set | index($n) | not) and .state == "OPEN"
                      and .status != "Done" and .status != "Released" and .wave != null) | .wave]
        | (max // 0) + 1' <<<"$board")"
    fi
  fi
  [[ "$start" =~ ^[0-9]+$ && "$cap" =~ ^[0-9]+$ && "$cap" -ge 1 ]] || die "--start and max parallel must be integers"
  local res; res="$(python3 -c "$PY" "$tmp/tasks.json" "$start" "$cap" "$tmp/outside.json")" || exit 1
  if [[ "$write" == 1 ]]; then
    local k
    for k in $(jq -r '.wave_of | keys[]' <<<"$res"); do
      "$BOARD" set-field "$k" wave "$(jq -r --arg k "$k" '.wave_of[$k]' <<<"$res")" >/dev/null
    done
    info "Wave written for $(jq '.wave_of | length' <<<"$res") task(s)"
  fi
  echo "$res"
}

need jq python3
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  plan) need gh; cmd_plan "$@" ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
