#!/usr/bin/env bash
# Create (or recreate) the kind cluster used by every lab. ~1-2 min.
set -euo pipefail
cd "$(dirname "$0")"
if kind get clusters 2>/dev/null | grep -qx nr-workshop; then
  echo "cluster nr-workshop already exists. To reset: kind delete cluster --name nr-workshop"
else
  kind create cluster --config kind-config.yaml
fi
kubectl config use-context kind-nr-workshop
kubectl get nodes
echo ">> Keep ONE WSL terminal open (e.g. k9s) for the whole workshop - WSL2 shuts the VM down when the last shell exits."
echo ">> If the API server refuses connections after a WSL restart: docker start nr-workshop-control-plane && sleep 60"
