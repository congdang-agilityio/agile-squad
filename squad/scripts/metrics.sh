#!/usr/bin/env bash
# metrics.sh: delivery metrics for the report skill. Every number is computed from GitHub data.
#
# Usage:
#   metrics.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD]   period (default: the last 7 days)
#   metrics.sh --milestone "<title>"                         one milestone (all time)
#
# Output JSON:
#   board              current items per type and status, flagged items (needs-human,
#                      needs-split, blocked)
#   delivered          stories and tasks/bugs that reached Done/Released in the period
#                      (time of the last Status change)
#   prs                merged PRs: count; for PRs that close a task or bug ("task_prs"): average
#                      and max changed lines/files as pr-size.sh counts them (tests, lockfiles and
#                      generated files excluded); other PRs (docs, setup) listed separately;
#                      PRs sent back by review
#                      (review:changes) and PRs that needed a rebase (needs-rebase)
#   bugs               opened / closed in the period, open now by priority
#   qa                 first-time QA pass rate: delivered tasks without any bug sub-issue
#   cycle_time_hours   "Started by dev-<k>" comment → Done; items without the comment are
#                      listed in "excluded", never estimated
#   parallelism        max number of tasks being developed at the same time ("Started by"
#                      → PR opened), and the intervals used
#   deployments        deploy workflow runs (by conclusion) and published releases
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

since="" until_="" milestone=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) since="${2:?}"; shift 2 ;;
    --until) until_="${2:?}"; shift 2 ;;
    --milestone) milestone="${2:?}"; shift 2 ;;
    -h|--help) usage_from "$0"; exit 0 ;;
    *) die "unknown argument $1 (see --help)" ;;
  esac
done
need gh jq python3
load_project
[[ -n "$since" ]] || since="$(date -u -d '7 days ago' +%F)"
[[ -n "$until_" ]] || until_="$(date -u -d tomorrow +%F)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---- board items with the time of the last Status change
Q='query($id:ID!,$endCursor:String){node(id:$id){... on ProjectV2{items(first:100,after:$endCursor){
  pageInfo{hasNextPage endCursor}
  nodes{isArchived content{... on Issue{number title state createdAt closedAt repository{nameWithOwner}
    labels(first:30){nodes{name}} milestone{title} parent{number}
    closedByPullRequestsReferences(first:5){nodes{number createdAt}}}}
    status: fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name updatedAt}}
    priority: fieldValueByName(name:"Priority"){... on ProjectV2ItemFieldSingleSelectValue{name}}
    attempts: fieldValueByName(name:"Attempts"){... on ProjectV2ItemFieldNumberValue{number}}}}}}}'
gh api graphql --paginate -f query="$Q" -F id="$PROJECT_ID" \
  | jq -s --arg repo "$OWNER/$REPO" '[.[].data.node.items.nodes[]
      | select((.isArchived | not) and .content.repository.nameWithOwner == $repo)
      | .content + {status: .status.name, status_at: .status.updatedAt, priority: .priority.name,
                    attempts: (.attempts.number // 0 | floor),
                    labels: [.content.labels.nodes[].name], milestone: .content.milestone.title,
                    parent: .content.parent.number,
                    prs: [.content.closedByPullRequestsReferences.nodes[] | {number, createdAt}]}
      | del(.repository, .closedByPullRequestsReferences)]' > "$T/items.json"

# ---- "Started by dev-<k>" comments for tasks and bugs that are or were in development
for n in $(jq -r '.[] | select((.labels | index("type:task") or index("type:bug"))
                  and .status != "Todo" and .status != "Backlog") | .number' "$T/items.json"); do
  gh api "repos/$OWNER/$REPO/issues/$n/comments?per_page=100" \
    --jq "[.[] | select(.body | test(\"^Started by dev-[0-9]+\")) | .created_at] | {n: $n, started: (min // null)}"
done | jq -s 'map({(.n | tostring): .started}) | add // {}' > "$T/started.json"

# ---- merged PRs (with label history for review:changes / needs-rebase)
gh pr list --repo "$OWNER/$REPO" --state merged --limit 300 \
  --json number,title,additions,deletions,changedFiles,mergedAt,createdAt,closingIssuesReferences > "$T/prs_all.json"
jq --arg s "$since" --arg u "$until_" '[.[] | select(.mergedAt >= $s and .mergedAt < $u)]' "$T/prs_all.json" > "$T/prs.json"
for p in $(jq -r '.[].number' "$T/prs_all.json"); do
  gh api "repos/$OWNER/$REPO/issues/$p/events?per_page=100" \
    --jq "{pr: $p, labels: [.[] | select(.event == \"labeled\") | .label.name] | unique}"
done | jq -s . > "$T/pr_labels.json"

# ---- size of every merged PR as pr-size.sh counts it (excludes tests, lockfiles, generated)
if [[ -n "$milestone" ]]; then   # only PRs that close an issue of the milestone
  sel="$(jq -c --arg m "$milestone" '[.[] | select(.milestone == $m) | .number]' "$T/items.json")"
  jq --argjson s "$sel" '[.[] | select(any(.closingIssuesReferences[]; .number as $n | $s | index($n)))]' \
    "$T/prs_all.json" > "$T/prs_sized.json"
else cp "$T/prs.json" "$T/prs_sized.json"; fi
for p in $(jq -r '.[].number' "$T/prs_sized.json"); do
  "$SQUAD_SCRIPTS/pr-size.sh" "$p" --size M 2>/dev/null | jq -c --argjson p "$p" '{pr: $p, lines, files}' || true
done | jq -s 'map({(.pr | tostring): {lines, files}}) | add // {}' > "$T/sizes.json"

# ---- bugs, deploy runs, releases
gh issue list --repo "$OWNER/$REPO" --label type:bug --state all --limit 500 \
  --json number,title,state,createdAt,closedAt > "$T/bugs.json"
wf="$(cfg '.deploy.staging_workflow')"; wf="${wf:-deploy.yml}"
gh run list --repo "$OWNER/$REPO" --workflow "$wf" --limit 200 \
  --json databaseId,event,conclusion,createdAt,headSha 2>/dev/null > "$T/runs.json" || echo '[]' > "$T/runs.json"
gh release list --repo "$OWNER/$REPO" --limit 100 --json tagName,publishedAt,isDraft > "$T/releases.json"

python3 - "$T" "$since" "$until_" "$milestone" <<'PY'
import json, sys, statistics
from datetime import datetime
T, since, until, milestone = sys.argv[1:5]
L = lambda f: json.load(open(f"{T}/{f}.json"))
items, started, prs_all, prs, pr_labels = L("items"), L("started"), L("prs_all"), L("prs"), L("pr_labels")
sizes = L("sizes")
bugs, runs, releases = L("bugs"), L("runs"), L("releases")
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
typ = lambda i: next((l[5:] for l in i["labels"] if l.startswith("type:")), "other")
in_period = lambda s: s is not None and since <= s < until

if milestone:
    ms_nums = {i["number"] for i in items if i.get("milestone") == milestone}
    keep = lambda i: i["number"] in ms_nums
    pr_keep = lambda p: any(r["number"] in ms_nums for r in p.get("closingIssuesReferences", []))
    prs = [p for p in prs_all if pr_keep(p)]
    window = lambda s: s is not None
else:
    keep = lambda i: True
    window = in_period

board = {}
for i in items:
    board.setdefault(typ(i), {}).setdefault(i["status"] or "none", 0)
    board[typ(i)][i["status"] or "none"] += 1
flags = {f: sorted(i["number"] for i in items if f in i["labels"] and i["state"] == "OPEN")
         for f in ("needs-human", "needs-split", "blocked")}

done = [i for i in items if keep(i) and i["status"] in ("Done", "Released") and window(i["status_at"])]
d_stories = [i for i in done if typ(i) == "story"]
d_work = [i for i in done if typ(i) in ("task", "bug")]

work_nums = {i["number"] for i in items if typ(i) in ("task", "bug")}
task_prs = [p for p in prs if any(r["number"] in work_nums for r in p.get("closingIssuesReferences", []))]
lines = [sizes[str(p["number"])]["lines"] for p in task_prs if str(p["number"]) in sizes]
files = [sizes[str(p["number"])]["files"] for p in task_prs if str(p["number"]) in sizes]
lab = {x["pr"]: set(x["labels"]) for x in pr_labels}
merged_nums = {p["number"] for p in prs}

bug_children = {}
for i in items:
    if typ(i) == "bug" and i.get("parent"):
        bug_children.setdefault(i["parent"], []).append(i["number"])
qa_tasks = [i for i in d_work if typ(i) == "task"]
first_pass = [i for i in qa_tasks if not bug_children.get(i["number"])]

cycle, excluded = [], []
for i in d_work:
    s = started.get(str(i["number"]))
    if s and i["status_at"]:
        cycle.append(round((ts(i["status_at"]) - ts(s)).total_seconds() / 3600, 2))
    else:
        excluded.append(i["number"])

intervals = []
for i in items:
    s = started.get(str(i["number"]))
    if not s or not i["prs"]:
        continue
    end = min(p["createdAt"] for p in i["prs"])
    if end > s and (milestone and keep(i) or not milestone and (in_period(s) or in_period(end))):
        intervals.append({"issue": i["number"], "start": s, "end": end})
events = sorted([(x["start"], 1) for x in intervals] + [(x["end"], -1) for x in intervals],
                key=lambda e: (e[0], e[1]))
cur = peak = 0
for _, d in events:
    cur += d; peak = max(peak, cur)

runs_p = [r for r in runs if in_period(r["createdAt"])] if not milestone else runs
rel_p = [r for r in releases if not r["isDraft"] and r["publishedAt"] and (milestone or in_period(r["publishedAt"]))]
if milestone:
    tag = milestone.split()[0]
    rel_p = [r for r in rel_p if r["tagName"] == tag]

prio = {i["number"]: i.get("priority") for i in items}
open_bugs = [b for b in bugs if b["state"] == "OPEN"]
out = {
    "scope": {"milestone": milestone} if milestone else {"since": since, "until": until},
    "board": {"by_type_and_status": board, "flagged": flags},
    "delivered": {"stories": len(d_stories), "story_list": [[i["number"], i["title"]] for i in d_stories],
                  "tasks_and_bugs": len(d_work), "task_list": [[i["number"], i["title"], i["status"]] for i in d_work]},
    "prs": {"merged": len(prs), "task_prs": len(task_prs), "other_prs": sorted(p["number"] for p in prs if p not in task_prs),
            "avg_changed_lines": round(sum(lines) / len(lines), 1) if lines else None,
            "max_changed_lines": max(lines) if lines else None,
            "avg_changed_files": round(sum(files) / len(files), 1) if files else None,
            "sent_back_by_review": sorted(n for n in merged_nums if "review:changes" in lab.get(n, ())),
            "needed_rebase": sorted(n for n in merged_nums if "needs-rebase" in lab.get(n, ()))},
    "bugs": {"opened": len([b for b in bugs if window(b["createdAt"])]),
             "closed": len([b for b in bugs if window(b["closedAt"])]),
             "open_now": {p: len([b for b in open_bugs if prio.get(b["number"]) == p]) for p in ("P0", "P1", "P2", "P3")}},
    "qa": {"tasks_delivered": len(qa_tasks), "passed_first_time": len(first_pass),
           "first_time_pass_rate": round(len(first_pass) / len(qa_tasks), 2) if qa_tasks else None,
           "tasks_with_bugs": sorted(i["number"] for i in qa_tasks if bug_children.get(i["number"]))},
    "cycle_time_hours": {"n": len(cycle), "avg": round(statistics.mean(cycle), 2) if cycle else None,
                         "median": round(statistics.median(cycle), 2) if cycle else None, "excluded": sorted(excluded)},
    "parallelism": {"max_concurrent_devs": peak, "intervals": intervals},
    "deployments": {"runs": len(runs_p),
                    "by_conclusion": {c: len([r for r in runs_p if r["conclusion"] == c]) for c in {r["conclusion"] for r in runs_p}},
                    "releases": [r["tagName"] for r in rel_p]},
}
print(json.dumps(out, indent=1))
PY
