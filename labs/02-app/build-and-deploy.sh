#!/usr/bin/env bash
# Clone SimplCommerce into the WSL filesystem, copy the deploy kit in, build, kind-load, deploy.
# Usage: bash build-and-deploy.sh [tag]     (default tag v1)
set -euo pipefail
TAG="${1:-v1}"
KIT="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="https://dev.azure.com/loctad/application/_git/SimplCommerce"

mkdir -p ~/src && cd ~/src
[ -d SimplCommerce ] || git clone "$REPO_URL"
cd SimplCommerce
mkdir -p deploy/local/k8s
cp "$KIT/Dockerfile" deploy/local/Dockerfile
cp "$KIT"/k8s/*.yaml deploy/local/k8s/

echo "== build (first time 10-20 min) =="
docker build -f deploy/local/Dockerfile -t "simplcommerce:$TAG" .
kind load docker-image "simplcommerce:$TAG" --name nr-workshop
docker exec nr-workshop-control-plane crictl images | grep simplcommerce

echo "== deploy =="
kubectl apply -f deploy/local/k8s/namespace.yaml
kubectl apply -f deploy/local/k8s/mssql.yaml
kubectl -n simplcommerce rollout status deployment/mssql --timeout=300s
sed "s|__IMAGE__|simplcommerce:$TAG|g" deploy/local/k8s/app.yaml | kubectl apply -f -
kubectl -n simplcommerce rollout status deployment/simplcommerce --timeout=600s
kubectl apply -f deploy/local/k8s/loadgen.yaml
kubectl -n simplcommerce rollout status deployment/loadgen --timeout=180s

echo "== verify =="
curl -is http://localhost:8080/health | head -1
kubectl -n simplcommerce logs deploy/loadgen --tail=5
echo ">> open http://localhost:8080 in the Windows browser"
