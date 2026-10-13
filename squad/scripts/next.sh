#!/usr/bin/env bash
# next.sh: the PM's view of what to do next (run skill). Read-only.
#
# Usage:
#   next.sh [--scope <issue>[,<issue>...]]
#
# --scope limits work items to those issues and their descendants (epic → story → task/bug).
# Output JSON {actions: [...], notes: [...], counts: {...}}: actions in priority order:
#   notify_needs_human  open items labeled needs-human (tell the stakeholder, then skip them)
#   ask_stakeholder     requirement folders with open/answered questions and no sign-off
#   gate_3              a deploy run is waiting for production approval
#   deploy_finish       a release is drafted and its deploy run has moved past the approval
#   qa                  items in QA without open child bugs
#   lead_merge          open PRs labeled review:passed
#   review              open PRs of tasks In Review with no verdict label
#   rebase              open PRs labeled needs-rebase
#   plan                Backlog stories, needs-split tasks, Todo bugs without a Wave (one action)
#   dev                 ready tasks of the lowest ready wave (mode implement or rework), limited
#                       by free developer slots and parallel.max_open_prs
#   deploy_release      open milestones whose deploy gate passes and that have no draft release
# An empty "actions" list means nothing is left: report and stop.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scope=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) scope="${2:?}"; shift 2 ;;
    -h|--help) usage_from "$0"; exit 0 ;;
    *) die "unknown argument $1 (see --help)" ;;
  esac
done
need gh jq python3
load_project
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

Q='query($id:ID!,$endCursor:String){node(id:$id){... on ProjectV2{items(first:100,after:$endCursor){
  pageInfo{hasNextPage endCursor}
  nodes{isArchived content{... on Issue{number title state body repository{nameWithOwner}
    labels(first:30){nodes{name}} milestone{title} parent{number}}}
    status: fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}
    priority: fieldValueByName(name:"Priority"){... on ProjectV2ItemFieldSingleSelectValue{name}}
    wave: fieldValueByName(name:"Wave"){... on ProjectV2ItemFieldNumberValue{number}}
    agent: fieldValueByName(name:"Agent"){... on ProjectV2ItemFieldTextValue{text}}}}}}}'
gh api graphql --paginate -f query="$Q" -F id="$PROJECT_ID" \
  | jq -s --arg repo "$OWNER/$REPO" '[.[].data.node.items.nodes[]
      | select((.isArchived | not) and .content.repository.nameWithOwner == $repo)
      | .content + {status: .status.name, priority: .priority.name, wave: (.wave.number | if . == null then null else floor end),
                    agent: .agent.text, labels: [.content.labels.nodes[].name],
                    milestone: .content.milestone.title, parent: .content.parent.number}
      | del(.repository)]' > "$T/items.json"
gh pr list --repo "$OWNER/$REPO" --state open --limit 200 \
  --json number,title,labels,headRefName,isDraft,closingIssuesReferences > "$T/prs.json"
gh api "repos/$OWNER/$REPO/milestones?state=open&per_page=100" > "$T/milestones.json"
gh api "repos/$OWNER/$REPO/releases?per_page=30" --jq '[.[] | select(.draft) | {name, tag_name, id}]' > "$T/drafts.json"
wf="$(cfg '.deploy.staging_workflow')"; wf="${wf:-deploy.yml}"
gh run list --repo "$OWNER/$REPO" --workflow "$wf" --event workflow_dispatch --limit 10 \
  --json databaseId,status,conclusion,url,createdAt 2>/dev/null > "$T/runs.json" || echo '[]' > "$T/runs.json"
: > "$T/gates.jsonl"
for m in $(jq -r '.[].title | @base64' "$T/milestones.json"); do
  t="$(base64 -d <<<"$m")"
  "$SQUAD_SCRIPTS/release.sh" gate "$t" 2>/dev/null | jq -c '{milestone, tag, ok}' >> "$T/gates.jsonl" || true
done
jq -s . "$T/gates.jsonl" > "$T/gates.json"
root="$(dirname "$(dirname "$(config_path)")")"
: > "$T/reqs.jsonl"
for d in "$root"/docs/requirements/*/; do
  [[ -f "$d/questions.md" ]] || continue
  slug="$(basename "$d")"
  signed=false; grep -q '^Signed-off: ' "$d/requirements.md" 2>/dev/null && signed=true
  open="$(grep -cE '^\s*-\s*\*\*Status:\*\*\s*(open|answered)\b' "$d/questions.md" || true)"
  jq -nc --arg s "$slug" --argjson signed "$signed" --argjson open "${open:-0}" '{slug:$s, signed:$signed, open:$open}' >> "$T/reqs.jsonl"
done
jq -s . "$T/reqs.jsonl" > "$T/reqs.json"
"$SQUAD_SCRIPTS/board.sh" ready-tasks > "$T/ready.json"

python3 - "$T" "$scope" "$(cfg '.parallel.max_parallel_dev')" "$(cfg '.parallel.max_open_prs')" <<'PY'
import json, sys
T, scope, maxdev, maxpr = sys.argv[1], sys.argv[2], int(sys.argv[3] or 2), int(sys.argv[4] or 4)
L = lambda f: json.load(open(f"{T}/{f}.json"))
items, prs, gates, drafts, runs, reqs, ready = L("items"), L("prs"), L("gates"), L("drafts"), L("runs"), L("reqs"), L("ready")
by = {i["number"]: i for i in items}
typ = lambda i: next((l[5:] for l in i["labels"] if l.startswith("type:")), "other")

roots = {int(x.strip().lstrip("#")) for x in scope.split(",") if x.strip()} if scope else set()
def in_scope(n, depth=0):
    if not roots: return True
    if n in roots: return True
    p = by.get(n, {}).get("parent")
    return p is not None and depth < 5 and in_scope(p, depth + 1)

def children_bugs_open(n):
    return [i["number"] for i in items if i.get("parent") == n and typ(i) == "bug"
            and i["status"] not in ("Done", "Released") and i["state"] == "OPEN"]

def pr_task(p):
    refs = [r["number"] for r in p.get("closingIssuesReferences", [])]
    return refs[0] if refs else None

actions, notes = [], []
labels = lambda p: {l["name"] for l in p["labels"]}

human = sorted(i["number"] for i in items if "needs-human" in i["labels"] and i["state"] == "OPEN" and in_scope(i["number"]))
if human: actions.append({"action": "notify_needs_human", "issues": human})

for r in reqs:
    if not r["signed"] and r["open"] > 0:
        actions.append({"action": "ask_stakeholder", "slug": r["slug"], "open_questions": r["open"]})

draft_names = {d["name"] for d in drafts} | {d["tag_name"] for d in drafts}
latest = runs[0] if runs else None
if latest and latest["status"] == "waiting":
    actions.append({"action": "gate_3", "run_id": latest["databaseId"], "run_url": latest["url"]})
elif drafts and latest and latest["status"] != "waiting":
    for g in gates:
        if g["tag"] in draft_names:
            actions.append({"action": "deploy_finish", "milestone": g["milestone"], "run_id": latest["databaseId"],
                            "run_status": latest["status"], "run_conclusion": latest["conclusion"]})

skip = {"needs-human"}
qa = [i for i in items if i["status"] == "QA" and i["state"] in ("OPEN", "CLOSED") and in_scope(i["number"])
      and typ(i) in ("task", "bug") and not skip & set(i["labels"])]
for i in sorted(qa, key=lambda i: (i.get("priority") or "P9", i["number"])):
    ob = children_bugs_open(i["number"])
    if ob:
        notes.append(f"#{i['number']} waits in QA for bugs {ob}")
    else:
        actions.append({"action": "qa", "issue": i["number"]})

for p in prs:
    t = pr_task(p)
    if t is not None and not in_scope(t): continue
    lb = labels(p)
    if "needs-human" in lb or (t and "needs-human" in by.get(t, {}).get("labels", [])): continue
    if "review:passed" in lb and not lb & {"needs-rebase", "needs-split"}:
        actions.append({"action": "lead_merge", "pr": p["number"], "issue": t})
for p in prs:
    t = pr_task(p)
    if t is not None and not in_scope(t): continue
    lb = labels(p)
    st = by.get(t, {}).get("status") if t else None
    if st == "In Review" and not lb & {"review:passed", "review:changes", "needs-rebase", "needs-split", "needs-human"} and not p["isDraft"]:
        actions.append({"action": "review", "pr": p["number"], "issue": t})
for p in prs:
    t = pr_task(p)
    if t is not None and not in_scope(t): continue
    if "needs-rebase" in labels(p) and "needs-human" not in labels(p):
        actions.append({"action": "rebase", "pr": p["number"], "issue": t})

stories = [i["number"] for i in items if typ(i) == "story" and i["status"] == "Backlog" and in_scope(i["number"]) and i["state"] == "OPEN"]
splits = [i["number"] for i in items if "needs-split" in i["labels"] and i["state"] == "OPEN" and in_scope(i["number"])]
parked = lambda i: "needs-human" in i["labels"] or "needs-human" in by.get(i.get("parent"), {}).get("labels", [])
bugs = [i["number"] for i in items if typ(i) == "bug" and i["status"] == "Todo" and i.get("wave") is None
        and i["state"] == "OPEN" and in_scope(i["number"]) and not parked(i)]
if (stories and roots) or splits or bugs:
    actions.append({"action": "plan", "stories": stories if roots else [], "tasks": splits + bugs})
if stories and not roots:
    notes.append(f"{len(stories)} stories in Backlog; pass --scope to plan specific epics or stories")

in_progress = [i for i in items if i["status"] == "In Progress" and typ(i) in ("task", "bug")]
in_review = [p for p in prs if pr_task(p) and by.get(pr_task(p), {}).get("status") == "In Review"]
busy = {i.get("agent") for i in in_progress if i.get("agent")}
free = [f"{k}" for k in range(1, maxdev + 1) if f"dev-{k}" not in busy]
cands = [r for r in ready if in_scope(r["number"])]
if cands and free and len(in_review) < maxpr:
    waves = sorted({r.get("wave") if r.get("wave") is not None else 10**6 for r in cands})
    low = waves[0]
    batch = [r for r in cands if (r.get("wave") if r.get("wave") is not None else 10**6) == low]
    open_pr_for = {pr_task(p): p for p in prs}
    for r, slot in zip(batch, free):
        p = open_pr_for.get(r["number"])
        mode = "rework" if p and "review:changes" in labels(p) else "implement"
        actions.append({"action": "dev", "issue": r["number"], "slot": int(slot), "mode": mode,
                        "wave": None if low == 10**6 else low})
elif cands and len(in_review) >= maxpr:
    notes.append(f"{len(in_review)} PRs in review (max_open_prs {maxpr}): no new developers")

for g in gates:
    if g["ok"] and g["tag"] not in draft_names and not any(a["action"] in ("gate_3", "deploy_finish") for a in actions):
        actions.append({"action": "deploy_release", "milestone": g["milestone"]})

counts = {"in_progress": len(in_progress), "in_review_prs": len(in_review), "free_slots": len(free),
          "ready_in_scope": len(cands)}
print(json.dumps({"scope": sorted(roots), "actions": actions, "notes": notes, "counts": counts}, indent=1))
PY
