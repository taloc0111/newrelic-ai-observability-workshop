#!/usr/bin/env bash
# Step 4 - New Relic on the kind cluster: nri-bundle (infrastructure, events, logs, KSM, k8s-agents-operator)
# + the Instrumentation CR for SimplCommerce, then restart the app so the .NET agent is injected at pod start.
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"

helm repo add newrelic https://helm-charts.newrelic.com >/dev/null 2>&1 || true
helm repo update >/dev/null

EXTRA=()
[ "${NEW_RELIC_REGION:-US}" = "EU" ] && EXTRA+=(--set global.nrStaging=false --set "global.customAttributes.region=eu")

helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace newrelic --create-namespace \
  -f values.yaml \
  --set global.licenseKey="$NEW_RELIC_LICENSE_KEY" \
  "${EXTRA[@]}" \
  --timeout 10m --wait

echo "== bundle pods =="
kubectl -n newrelic get pods

echo "== Instrumentation CRD version served by this operator =="
CRD_VER=$(kubectl get crd instrumentations.newrelic.com -o jsonpath='{.spec.versions[?(@.storage==true)].name}')
echo "storage version: $CRD_VER   (instrumentation.yaml uses newrelic.com/v1beta3; edit apiVersion if different)"
sed "s|newrelic.com/v1beta3|newrelic.com/$CRD_VER|" instrumentation.yaml | kubectl apply -f -

# The agent is injected at pod START - restart the app so its pod gets the initContainer and env.
kubectl -n simplcommerce rollout restart deployment/simplcommerce
kubectl -n simplcommerce rollout status deployment/simplcommerce --timeout=600s

echo "== injection proof (expect an initContainer with 'newrelic' in its name + CORECLR_PROFILER / NEW_RELIC_APP_NAME env) =="
POD=$(kubectl -n simplcommerce get pod -l app=simplcommerce -o jsonpath='{.items[0].metadata.name}')
kubectl -n simplcommerce get pod "$POD" -o jsonpath='{.spec.initContainers[*].name}'; echo
kubectl -n simplcommerce get pod "$POD" -o jsonpath='{range .spec.containers[?(@.name=="web")].env[*]}{.name}{"\n"}{end}' | grep -E "CORECLR|^NEW_RELIC_" | head
kubectl -n simplcommerce get secret newrelic-key-secret >/dev/null 2>&1 && echo "newrelic-key-secret present in simplcommerce (copied by the operator)" \
  || echo "WARN: newrelic-key-secret missing in simplcommerce - the operator did not replicate the license key; see Appendix C"

echo ">> New Relic UI ($NR_UI): Kubernetes -> cluster nr-workshop; APM & Services -> SimplCommerce (wait ~3-5 min of loadgen traffic)."
echo ">> NRQL check:  SELECT count(*) FROM Transaction WHERE appName = 'SimplCommerce' SINCE 10 minutes ago"
