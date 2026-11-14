#!/usr/bin/env bash
# Lab 7 - AI Monitoring. Build, load and deploy the toy LLM service, then generate a few LLM calls.
# Needs: an OpenAI-compatible API key (or --ollama for the free in-cluster model) and the New Relic license key
# from ~/.nr-keys. Secrets land only in a Kubernetes Secret - never in k8s.yaml, never in the repo.
#
# Usage: bash run-demo.sh                # prompts for the LLM key (OpenAI / Azure OpenAI / any /v1 endpoint)
#   env overrides: OPENAI_BASE_URL=https://.../v1  MODEL=gpt-4o-mini  (defaults: api.openai.com, gpt-4o-mini)
#   --ollama: use the free in-cluster model from setup-ollama.sh (no key): base URL http://ollama:11434/v1, model qwen2.5:0.5b
set -euo pipefail
source ~/.nr-keys
cd "$(dirname "$0")"
NS=simplcommerce

if [ "${1:-}" = "--ollama" ]; then
  OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://ollama:11434/v1}"
  MODEL="${MODEL:-qwen2.5:0.5b}"
  OPENAI_API_KEY="${OPENAI_API_KEY:-ollama}"          # any non-empty string; Ollama ignores it
  kubectl -n $NS get deploy ollama >/dev/null 2>&1 || { echo "Ollama not deployed - run: bash setup-ollama.sh"; exit 1; }
fi
if [ -z "${OPENAI_API_KEY:-}" ]; then read -srp "OpenAI-compatible API key: " OPENAI_API_KEY; echo; fi
MODEL="${MODEL:-gpt-4o-mini}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
NR_HOST="${NEW_RELIC_HOST:-collector.newrelic.com}"

echo "== build + load =="
docker build -q -t ai-descgen:v1 .
kind load docker-image ai-descgen:v1 --name nr-workshop

echo "== secret (Kubernetes only) =="
kubectl -n $NS create secret generic ai-descgen-secret \
  --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
  --from-literal=NEW_RELIC_LICENSE_KEY="$NEW_RELIC_LICENSE_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
unset OPENAI_API_KEY

echo "== deploy =="
sed "s|__MODEL__|$MODEL|g; s|__OPENAI_BASE_URL__|$OPENAI_BASE_URL|g; s|__NR_HOST__|$NR_HOST|g" k8s.yaml | kubectl apply -f -
kubectl -n $NS rollout restart deploy/ai-descgen >/dev/null   # pods read the Secret at start: pick up a re-entered key
kubectl -n $NS rollout status deploy/ai-descgen --timeout=300s

echo "== 5 LLM calls from the loadgen pod =="
for p in camera laptop headphones "running shoes" "coffee maker"; do
  kubectl -n $NS exec deploy/loadgen -- curl -s --max-time 120 "http://ai-descgen/describe?product=$(echo "$p" | sed 's/ /%20/g')"; echo
done
echo ">> New Relic ($NR_UI): AI Monitoring -> ai-descgen: requests, tokens, response time, errors; the AI Traces view shows prompt + completion."
echo ">> NRQL: SELECT request.model, response.usage.total_tokens, duration FROM LlmChatCompletionSummary WHERE appName = 'ai-descgen' SINCE 30 minutes ago"
echo ">> Errors? kubectl -n $NS logs deploy/ai-descgen --tail=50   (401 = LLM key; connection refused = base URL;"
echo "   'Unable to connect to collector' or 'license key invalid' = NEW_RELIC_LICENSE_KEY / NEW_RELIC_HOST (EU accounts need collector.eu01.nr-data.net))"
