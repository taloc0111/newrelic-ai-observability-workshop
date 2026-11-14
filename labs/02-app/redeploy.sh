#!/usr/bin/env bash
# Rebuild + roll out a new tag (hotfix path). Usage: bash redeploy.sh v2
# After the rollout, record the deployment in New Relic change tracking so the
# marker shows on APM charts and the Issue page (labs/06-faults/record-deployment.sh).
set -euo pipefail
TAG="${1:?tag required, e.g. v2}"
cd ~/src/SimplCommerce
docker build -f deploy/local/Dockerfile -t "simplcommerce:$TAG" .
kind load docker-image "simplcommerce:$TAG" --name nr-workshop
kubectl -n simplcommerce set image deployment/simplcommerce migrate="simplcommerce:$TAG" web="simplcommerce:$TAG"
kubectl -n simplcommerce rollout status deployment/simplcommerce
# roll back: kubectl -n simplcommerce rollout undo deployment/simplcommerce
[ -f ~/.nr-keys ] && bash ~/nr-training/labs/06-faults/record-deployment.sh "$TAG" "redeploy.sh $TAG" || true
