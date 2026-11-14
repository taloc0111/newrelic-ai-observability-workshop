#!/usr/bin/env bash
# Lab 6 (optional) - predictive alert condition as code (NerdGraph accepted the prediction block on 2026-11-07).
# Create it AFTER the Lab 3 outage demo, or keep it disabled during the session: it reacts to the outage history
# (0 rpm for 15 min) with a "Predicted: ... < 10" event hours ahead that merges into the Lab 3 issue and keeps it open.
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"
NG="python3 ../lib/nerdgraph.py"
POLICY_ID=$(cat ~/.nr-policy-id 2>/dev/null || true)
[ -n "$POLICY_ID" ] || { echo "run labs/04-alerts/create-alert-policy.sh first"; exit 1; }
NAME="SimplCommerce throughput predicted low"
QUERY="SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName = 'SimplCommerce'"
$NG condition-predictive.graphql accountId="$NEW_RELIC_ACCOUNT_ID" policyId="$POLICY_ID" name="$NAME" query="$QUERY" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["alertsNrqlConditionStaticCreate"]; print("created", d["name"], "id", d["id"])'
echo ">> Prove it: kubectl -n simplcommerce scale deploy/loadgen --replicas=0 and watch the forecast dive (then scale back to 1)."
