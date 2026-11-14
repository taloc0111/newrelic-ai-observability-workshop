#!/usr/bin/env bash
# Lab 7 - ask the model anything THROUGH the instrumented service, so the call shows up in New Relic
# (APM -> ai-descgen -> AI Traces, with prompt, answer and tokens; plus a span in the transaction trace).
# Usage: bash ask.sh "your question"        (prompts sent straight to Ollama - ollama run, port-forward - are NOT recorded)
set -euo pipefail
Q="${*:-Explain root cause analysis in two sentences.}"
kubectl -n simplcommerce exec deploy/loadgen -- curl -sS --max-time 120 --retry 3 --retry-connrefused --retry-delay 2 -G "http://ai-descgen/ask" --data-urlencode "q=$Q" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["answer"].strip()); print("-- model:", d["model"], "| tokens in/out:", d["tokens"]["input"], "/", d["tokens"]["output"])' 2>/dev/null \
  || kubectl -n simplcommerce exec deploy/loadgen -- curl -sS --max-time 120 --retry 3 --retry-connrefused --retry-delay 2 -G "http://ai-descgen/ask" --data-urlencode "q=$Q"
echo ">> 1-2 min later: APM -> ai-descgen -> AI Traces (or Query builder: SELECT * FROM LlmChatCompletionMessage WHERE appName = 'ai-descgen')."
