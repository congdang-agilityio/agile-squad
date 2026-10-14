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
#   deploy_finish       a release is drafted (or published with its milestone still open) and
#                       its deploy run has moved past the approval
#   qa                  items in QA without open child bugs
#                       (and open stories whose tasks are all Done: story check, "story": true)
#   lead_merge          open PRs labeled review:passed
#   review              open PRs of tasks In Review with no verdict label
#   rebase              open PRs labeled needs-rebase
#   plan                Backlog stories, needs-split tasks, Todo bugs without a Wave (one action)
#   dev                 ready tasks of the lowest ready wave (mode implement or rework), limited
#                       by free developer slots and parallel.max_open_prs
#   deploy_release      open milestones whose deploy gate passes and that have no draft release
# "unreleased": Done stories that belong to no milestone (the PM asks the stakeholder for one).
# "batch": the actions to dispatch together now (one per independent lane: deploy, qa, PR
# review/merge, rebase, plan, plus all dev actions), at most parallel.max_agents subagents; a
# pending stakeholder gate stands alone. "rewave": unstarted tasks whose waves should be
# recomputed (free slots idle while ready tasks wait in later waves).
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
  --json number,title,body,labels,headRefName,isDraft,closingIssuesReferences > "$T/prs.json"
gh api "repos/$OWNER/$REPO/milestones?state=open&per_page=100" > "$T/milestones.json"
gh api "repos/$OWNER/$REPO/releases?per_page=30" --jq '[.[] | {name, tag_name, id, draft}]' > "$T/drafts.json"
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

python3 - "$T" "$scope" "$(cfg '.parallel.max_parallel_dev')" "$(cfg '.parallel.max_open_prs')" "$(cfg '.parallel.max_agents')" <<'PY'
import json, sys
T, scope, maxdev, maxpr = sys.argv[1], sys.argv[2], int(sys.argv[3] or 2), int(sys.argv[4] or 4)
maxagents = int(sys.argv[5] or 3)
L = lambda f: json.load(open(f"{T}/{f}.json"))
items, prs, gates, drafts, runs, reqs, ready = L("items"), L("prs"), L("gates"), L("drafts"), L("runs"), L("reqs"), L("ready")
prs.sort(key=lambda p: p["number"])   # oldest PR first
by = {i["number"]: i for i in items}
typ = lambda i: next((l[5:] for l in i["labels"] if l.startswith("type:")), "other")

roots = {int(x.strip().lstrip("#")) for x in scope.split(",") if x.strip()} if scope else set()
def in_scope(n, depth=0):
    if not roots: return True
    if n in roots: return True
    p = by.get(n, {}).get("parent")
    return p is not None and depth < 5 and in_scope(p, depth + 1)

def children_bugs_open(n):
    # a merged fix closes the bug issue before QA has verified it: status decides, not state
    return [i["number"] for i in items if i.get("parent") == n and typ(i) == "bug"
            and i["status"] not in ("Done", "Released")]

import re
def pr_task(p):
    # GitHub links "Closes #N" with a delay: fall back to the body, then the branch name
    refs = [r["number"] for r in p.get("closingIssuesReferences", [])]
    if refs: return refs[0]
    m = re.search(r"(?i)\b(?:closes|fixes|resolves)\s+#(\d+)", p.get("body") or "")
    if m: return int(m.group(1))
    m = re.match(r"(?:feat|fix)/(\d+)-", p.get("headRefName") or "")
    return int(m.group(1)) if m else None

actions, notes = [], []
labels = lambda p: {l["name"] for l in p["labels"]}

human = sorted(i["number"] for i in items if "needs-human" in i["labels"] and i["state"] == "OPEN" and in_scope(i["number"]))
if human: actions.append({"action": "notify_needs_human", "issues": human})

for r in reqs:
    if not r["signed"] and r["open"] > 0:
        actions.append({"action": "ask_stakeholder", "slug": r["slug"], "open_questions": r["open"]})

# a draft release, or a published one whose milestone is still open (finish was interrupted)
draft_names = {n for d in drafts for n in (d["name"], d["tag_name"])}
latest = runs[0] if runs else None
if latest and latest["status"] == "waiting":
    actions.append({"action": "gate_3", "run_id": latest["databaseId"], "run_url": latest["url"]})
elif drafts and latest and latest["status"] != "waiting":
    for g in gates:
        if g["tag"] in draft_names:
            actions.append({"action": "deploy_finish", "milestone": g["milestone"], "run_id": latest["databaseId"],
                            "run_status": latest["status"], "run_conclusion": latest["conclusion"]})

skip = {"needs-human", "blocked"}
qa = [i for i in items if i["status"] == "QA" and i["state"] in ("OPEN", "CLOSED") and in_scope(i["number"])
      and typ(i) in ("task", "bug") and not skip & set(i["labels"])]
for i in sorted(qa, key=lambda i: (i.get("priority") or "P9", i["number"])):
    ob = children_bugs_open(i["number"])
    if ob:
        notes.append(f"#{i['number']} waits in QA for bugs {ob}")
    else:
        actions.append({"action": "qa", "issue": i["number"]})

# stories left open after their last task passed QA (e.g. waiting for a stakeholder answer,
# labeled blocked until the PM records it): QA checks the story itself
for s in items:
    if typ(s) != "story" or s["state"] != "OPEN" or s["status"] in ("Backlog", "Done", "Released"): continue
    if not in_scope(s["number"]) or {"needs-human", "blocked"} & set(s["labels"]): continue
    kids = [i for i in items if i.get("parent") == s["number"] and typ(i) in ("task", "bug")]
    if kids and all(i["status"] in ("Done", "Released") for i in kids) and not children_bugs_open(s["number"]) \
            and not any(a.get("issue") == s["number"] for a in actions):
        actions.append({"action": "qa", "issue": s["number"], "story": True})

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
planning = {t for a in actions if a["action"] == "plan" for t in a["tasks"]}
cands = [r for r in ready if in_scope(r["number"]) and r["number"] not in planning]
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

# batch: what can be dispatched together now, one action per independent lane, at most
# parallel.max_agents subagents. A requirements question stands alone; a pending GATE 3 only
# holds the deploy lane (it is in actions, never in the batch) while the team keeps working.
blocking = {"ask_stakeholder"}
lanes = {"deploy_finish": "deploy", "deploy_release": "deploy", "qa": "qa", "lead_merge": "pr",
         "review": "pr", "rebase": "rebase", "plan": "plan", "dev": "dev"}
batch, used = [], set()
first = next((a for a in actions if a["action"] not in ("notify_needs_human", "gate_3")), None)
if first and first["action"] in blocking:
    batch = [first]
else:
    for a in actions:
        lane = lanes.get(a["action"])
        if not lane or len(batch) >= maxagents: continue
        if lane == "dev" or lane not in used:
            if lane != "dev" and a.get("issue") and any(b.get("issue") == a.get("issue") for b in batch): continue
            batch.append(a); used.add(lane)

# rewave: free developer slots but the lowest wave has fewer ready tasks than slots, while
# ready tasks wait in later waves -> the Team Lead should recompute waves for unstarted tasks
rewave = []
dev_now = [a for a in actions if a["action"] == "dev"]
later = [r for r in cands if r.get("wave") is not None and dev_now and r.get("wave") != dev_now[0].get("wave")]
if dev_now and later and len(dev_now) < len(free):
    rewave = sorted(i["number"] for i in items if typ(i) in ("task", "bug") and i["status"] == "Todo"
                    and i["state"] == "OPEN" and i.get("wave") is not None and in_scope(i["number"])
                    and not {"needs-human", "needs-split", "blocked"} & set(i["labels"]))

# Done stories with Done tasks in no milestone: nothing will release them until the
# stakeholder names one
unreleased = sorted(s["number"] for s in items if typ(s) == "story" and s["status"] == "Done"
                    and any(i.get("parent") == s["number"] and i["status"] == "Done" and not i.get("milestone")
                            for i in items))
if unreleased:
    notes.append(f"stories Done without a milestone (not releasable yet): {unreleased}")

counts = {"in_progress": len(in_progress), "in_review_prs": len(in_review), "free_slots": len(free),
          "ready_in_scope": len(cands)}
print(json.dumps({"scope": sorted(roots), "actions": actions, "batch": batch, "rewave": rewave, "unreleased": unreleased,
                  "notes": notes, "counts": counts}, indent=1))
PY
