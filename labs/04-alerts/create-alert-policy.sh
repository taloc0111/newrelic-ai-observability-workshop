#!/usr/bin/env bash
# Lab 1 - alerting as code via NerdGraph: policy "nr-workshop" + two NRQL conditions on SimplCommerce
#   gen 2  "SimplCommerce error rate > 5%"        static, fixed threshold (fires in Lab 3 and on faults.sh 500s)
#   gen 1  "SimplCommerce response time anomaly"  baseline, learns from history (quiet on a fresh account)
# Idempotent: reuses the policy by name, skips a condition whose name already exists. User key (NRAK-) required.
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"
NG="python3 ../lib/nerdgraph.py"
POLICY_NAME="nr-workshop"

POLICY_ID=$($NG find-policy.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$POLICY_NAME" \
  | python3 -c 'import json,sys; p=json.load(sys.stdin)["data"]["actor"]["account"]["alerts"]["policiesSearch"]["policies"]; print(p[0]["id"] if p else "")')
if [ -z "$POLICY_ID" ]; then
  POLICY_ID=$($NG policy.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$POLICY_NAME" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["alertsPolicyCreate"]["id"])')
  echo "created policy $POLICY_NAME id=$POLICY_ID"
else
  echo "policy $POLICY_NAME exists id=$POLICY_ID"
fi
echo "$POLICY_ID" > ~/.nr-policy-id     # other scripts (workflow, log condition, predictions) read this

EXISTING=$($NG list-conditions.graphql accountId="$NEW_RELIC_ACCOUNT_ID" policyId="$POLICY_ID" \
  | python3 -c 'import json,sys; print("\n".join(c["name"] for c in json.load(sys.stdin)["data"]["actor"]["account"]["alerts"]["nrqlConditionsSearch"]["nrqlConditions"]))')

create() {  # <graphql file> <condition name> <nrql>
  if grep -qxF "$2" <<<"$EXISTING"; then echo "condition exists: $2"; return; fi
  $NG "$1" accountId="$NEW_RELIC_ACCOUNT_ID" policyId="$POLICY_ID" name="$2" query="$3" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); d=r.get("data") or {}; k=next(iter(d), None)
if not (k and d[k]): sys.exit("FAILED: " + json.dumps(r.get("errors")))
print("created", d[k]["name"], "id", d[k]["id"])'
}

create condition-error-rate-static.graphql "SimplCommerce error rate > 5%" \
  "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'SimplCommerce'"
create condition-response-time-baseline.graphql "SimplCommerce response time anomaly" \
  "SELECT average(duration) FROM Transaction WHERE appName = 'SimplCommerce'"

echo ">> UI: Alerts -> Alert conditions (policies) -> $POLICY_NAME. Open the static condition: 60 s window on an event timer, above 5 for 1 min, loss of signal 3 min."
echo ">> Then: policy -> Settings -> tick 'Correlate and suppress noise' (off on a NerdGraph-created policy; without it alert events never merge)."
echo ">> Prove the fixed one: bash ~/nr-training/labs/06-faults/faults.sh 500s   (150 s burst: alert event ~3 min, issue + push ~4 min)"
