#!/usr/bin/env bash
# Record a deployment marker on the SimplCommerce APM entity (change tracking). Called by redeploy.sh, or by hand:
#   bash record-deployment.sh v2 "rollback after mssql outage"
set -euo pipefail
VERSION="${1:?version required}"
DESC="${2:-workshop deployment}"
source ~/.nr-keys
cd "$(dirname "$0")"
NG="python3 ../lib/nerdgraph.py"
GUID=$($NG entity-guid.graphql query="name = 'SimplCommerce' AND domain = 'APM' AND type = 'APPLICATION'" \
  | python3 -c 'import json,sys; e=json.load(sys.stdin)["data"]["actor"]["entitySearch"]["results"]["entities"]; print(e[0]["guid"] if e else "")')
[ -n "$GUID" ] || { echo "APM entity SimplCommerce not found yet (no traffic reported?)"; exit 1; }
$NG deployment.graphql entityGuid="$GUID" version="$VERSION" description="$DESC" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["changeTrackingCreateDeployment"]; print("deployment", d["deploymentId"], "version", d["version"])'
echo ">> UI: APM & Services -> SimplCommerce -> Change tracking (and the marker on the Summary charts)."
