#!/usr/bin/env bash
# List New Relic issues created in the last 30 min (open by default; pass ALL to include closed).
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"
python3 ../lib/nerdgraph.py issues.graphql accountId="$NEW_RELIC_ACCOUNT_ID" | python3 -c '
import json, sys, time
show_all = len(sys.argv) > 1 and sys.argv[1] == "ALL"
d = json.load(sys.stdin)
issues = d["data"]["actor"]["account"]["aiIssues"]["issues"]["issues"]
cut = (time.time() - 1800) * 1000
rows = [i for i in issues if (i.get("createdAt") or 0) >= cut and (show_all or i["state"] not in ("CLOSED",))]
print("total:", len(rows))
for i in sorted(rows, key=lambda x: x.get("createdAt") or 0):
    title = (i.get("title") or ["-"])[0]
    cond = (i.get("conditionName") or ["-"])[0]
    ents = ",".join(i.get("entityNames") or [])
    print("%s  %-9s %-8s %-45s cond: %-40s entities: %s  incidents: %d" % (
        i["issueId"][:8], i["state"], i["priority"], title[:45], cond[:40], ents, len(i.get("incidentIds") or [])))
' "${1:-}"
