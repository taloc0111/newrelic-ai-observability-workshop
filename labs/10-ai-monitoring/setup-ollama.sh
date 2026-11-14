#!/usr/bin/env bash
# Lab 7 - deploy Ollama in the kind cluster and pull a small model. Free, offline, OpenAI-compatible.
# Usage: bash setup-ollama.sh [model]      default model qwen2.5:0.5b (~400 MB, CPU-friendly). Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
NS=simplcommerce
MODEL="${1:-qwen2.5:0.5b}"

kubectl apply -f ollama.yaml
kubectl -n $NS rollout status deploy/ollama --timeout=300s

echo "== pulling $MODEL inside the pod (first time: a few minutes, depends on your download speed) =="
kubectl -n $NS exec deploy/ollama -- ollama pull "$MODEL"
kubectl -n $NS exec deploy/ollama -- ollama list

echo "== smoke test through the OpenAI-compatible endpoint =="
kubectl -n $NS exec deploy/loadgen -- curl -s --max-time 120 http://ollama:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in five words.\"}],\"max_tokens\":20}"
echo
echo ">> Now: bash run-demo.sh --ollama          (uses http://ollama:11434/v1, model $MODEL, no API key needed)"
