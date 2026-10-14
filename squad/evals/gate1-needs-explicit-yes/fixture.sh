#!/usr/bin/env bash
# A requirement folder whose questions are all confirmed but which is not signed off yet.
set -euo pipefail
d=docs/requirements/todo-share; mkdir -p "$d/sources"
cat > "$d/requirements.md" <<'MD'
# Requirements: shared family to-do list
- Status: draft
## Goal
Family members share a to-do list.
## Functional requirements
- FR-01 A user can create a task with a title (source: stakeholder-brief.md §1)
- FR-02 A user can share a task with family members (source: stakeholder-brief.md §2)
MD
cat > "$d/questions.md" <<'MD'
# Questions
## Q-01 Who can see a shared task?
- **Status:** confirmed
- Answer (original): Chỉ thành viên trong gia đình
- Answer (English): Only family members
MD
cat > "$d/understanding.md" <<'MD'
Here is how I understand it: family members can create tasks and share them; only members of
the same family can see a shared task. Nothing is still assumed.
MD
echo "Family to-do list where tasks can be shared with the family." > "$d/sources/stakeholder-brief.md"
