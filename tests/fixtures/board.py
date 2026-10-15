"""Render a compact board description into the two GraphQL shapes squad reads.
Usage: python3 board.py <items.json> next|board
items.json: [{number, type, status, title?, body?, labels?, priority?, size?, wave?, agent?,
              parent?, milestone?, state?, unlisted?}]
An item with "unlisted": true is left out of the listing (like GitHub's item listing sometimes
does) but still shows up as a parent of the items under it."""
import json, sys
items, shape = json.load(open(sys.argv[1])), sys.argv[2]
idx = {i["number"]: i for i in items}
def parent(n, depth=0):  # nested like GitHub's parent{number parent{...}}
    if not n or depth > 3: return None
    return {"number": n, "parent": parent(idx.get(n, {}).get("parent"), depth + 1)}
def content(i):
    labels = [f"type:{i['type']}"] + i.get("labels", [])
    return {"__typename": "Issue", "number": i["number"], "title": i.get("title", f"item {i['number']}"),
            "state": i.get("state", "OPEN"), "body": i.get("body", ""), "url": f"https://x/{i['number']}",
            "repository": {"nameWithOwner": "acme/app"}, "labels": {"nodes": [{"name": l} for l in labels]},
            "milestone": {"title": i["milestone"]} if i.get("milestone") else None,
            "parent": parent(i.get("parent"))}
nodes = []
for i in items:
    if i.get("unlisted"): continue
    if shape == "next":
        nodes.append({"isArchived": False, "content": content(i),
            "status": {"name": i["status"]} if i.get("status") else None,
            "priority": {"name": i["priority"]} if i.get("priority") else None,
            "size": {"name": i["size"]} if i.get("size") else None,
            "wave": {"number": i["wave"]} if i.get("wave") is not None else None,
            "agent": {"text": i["agent"]} if i.get("agent") else None,
            "attempts": {"number": i["attempts"]} if i.get("attempts") is not None else None})
    else:
        fv = []
        for f, k in (("Status", "status"), ("Priority", "priority"), ("Size", "size")):
            if i.get(k): fv.append({"__typename": "ProjectV2ItemFieldSingleSelectValue", "name": i[k], "field": {"name": f}})
        if i.get("wave") is not None: fv.append({"__typename": "ProjectV2ItemFieldNumberValue", "number": i["wave"], "field": {"name": "Wave"}})
        if i.get("agent"): fv.append({"__typename": "ProjectV2ItemFieldTextValue", "text": i["agent"], "field": {"name": "Agent"}})
        if i.get("attempts") is not None: fv.append({"__typename": "ProjectV2ItemFieldNumberValue", "number": i["attempts"], "field": {"name": "Attempts"}})
        nodes.append({"id": f"PVTI_{i['number']}", "isArchived": False, "content": content(i), "fieldValues": {"nodes": fv}})
print(json.dumps({"data": {"node": {"items": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}}}}))
