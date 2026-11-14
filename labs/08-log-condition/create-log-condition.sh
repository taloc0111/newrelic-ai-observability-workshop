#!/usr/bin/env bash
# Lab 5 - NRQL alert condition on error logs, as code (idempotent by name). Attaches to the Lab 1 policy.
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"
NG="python3 ../lib/nerdgraph.py"
POLICY_ID=$(cat ~/.nr-policy-id 2>/dev/null || true)
[ -n "$POLICY_ID" ] || { echo "run labs/04-alerts/create-alert-policy.sh first"; exit 1; }
NAME="simplcommerce error-log spike"
QUERY=$(grep -v '^--' condition.nrql | tr '\n' ' ' | sed 's/  */ /g; s/ *$//')

EXISTS=$($NG ../04-alerts/list-conditions.graphql accountId="$NEW_RELIC_ACCOUNT_ID" policyId="$POLICY_ID" \
  | python3 -c 'import json,sys; print(any(c["name"]==sys.argv[1] for c in json.load(sys.stdin)["data"]["actor"]["account"]["alerts"]["nrqlConditionsSearch"]["nrqlConditions"]))' "$NAME")
if [ "$EXISTS" = "True" ]; then echo "condition exists: $NAME"; else
  $NG condition-log-errors.graphql accountId="$NEW_RELIC_ACCOUNT_ID" policyId="$POLICY_ID" name="$NAME" query="$QUERY" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); d=(r.get("data") or {}).get("alertsNrqlConditionStaticCreate")
if not d: sys.exit("FAILED: " + json.dumps(r.get("errors")))
print("created", d["name"], "id", d["id"])'
fi
echo ">> Query builder first: $QUERY TIMESERIES 1 minute SINCE 30 minutes ago"
echo ">> Wait ~5 min for the new condition to start evaluating, then prove it fires: bash ~/nr-training/labs/06-faults/faults.sh throw"
echo ">> (150 s burst = ~150 ERROR lines); alert event ~3 min, merged with the Lab 1 error-rate event, issue closes ~4 min after the last error."
