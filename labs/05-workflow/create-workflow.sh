#!/usr/bin/env bash
# Lab 2 - issue -> ntfy push, as code: destination (webhook to ntfy.sh) + channel (payload template) + workflow
# (filter: the Lab 1 policy; triggers: ACTIVATED, CLOSED). Idempotent by name. User key required.
# Usage: bash create-workflow.sh <ntfy-topic>      (pick a random topic; subscribers open https://ntfy.sh/<topic>)
set -euo pipefail
TOPIC="${1:?ntfy topic required, e.g. nr-workshop-$RANDOM}"
source ~/.nr-keys
cd "$(dirname "$0")"
NG="python3 ../lib/nerdgraph.py"
NAME="nr-workshop-ntfy"
POLICY_ID=$(cat ~/.nr-policy-id 2>/dev/null || true)
[ -n "$POLICY_ID" ] || { echo "run labs/04-alerts/create-alert-policy.sh first (writes ~/.nr-policy-id)"; exit 1; }

FOUND=$($NG find-notifications.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$NAME")
pick() { python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["actor"]["account"]; e=d'"$1"'["entities"]; print(e[0]["id"] if e else "")' <<<"$FOUND"; }
DEST_ID=$(pick '["aiNotifications"]["destinations"]')
CHAN_ID=$(pick '["aiNotifications"]["channels"]')
WF_ID=$(pick '["aiWorkflows"]["workflows"]')

if [ -z "$DEST_ID" ]; then
  DEST_ID=$($NG destination.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$NAME" url="https://ntfy.sh" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["aiNotificationsCreateDestination"]; print(r["destination"]["id"] if r.get("destination") else sys.exit("destination error: %s" % r.get("error")))')
  echo "created destination $DEST_ID"
else echo "destination exists $DEST_ID"; fi

if [ -z "$CHAN_ID" ]; then
  sed "s|__NTFY_TOPIC__|$TOPIC|" channel-payload.json > /tmp/nr-channel-payload.json
  CHAN_ID=$($NG channel.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$NAME" destinationId="$DEST_ID" @payload=/tmp/nr-channel-payload.json \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["aiNotificationsCreateChannel"]; print(r["channel"]["id"] if r.get("channel") else sys.exit("channel error: %s" % r.get("error")))')
  echo "created channel $CHAN_ID (topic $TOPIC)"
else echo "channel exists $CHAN_ID - topic is whatever it was created with; delete it in the UI to change the topic"; fi

if [ -z "$WF_ID" ]; then
  WF_ID=$($NG workflow.graphql accountId="$NEW_RELIC_ACCOUNT_ID" name="$NAME" policyId="$POLICY_ID" channelId="$CHAN_ID" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["aiWorkflowsCreateWorkflow"]; print(r["workflow"]["id"] if r.get("workflow") else sys.exit("workflow error: %s" % r.get("errors")))')
  echo "created workflow $WF_ID"
else echo "workflow exists $WF_ID"; fi

echo ">> subscribe: open https://ntfy.sh/$TOPIC in a browser (or the ntfy app), then fire: bash ~/nr-training/labs/06-faults/faults.sh 500s"
echo ">> UI: Alerts -> Workflows -> $NAME (filter, channel, test button); Alerts -> Destinations -> $NAME."
