# New Relic AI-Powered Observability - lab kit

Hands-on labs for the New Relic AI features (Applied Intelligence / Incident Intelligence, NRQL baselines and Predictions, New Relic AI, Workflows, AI Monitoring, the AI MCP Server), run against **SimplCommerce** (.NET 8 + SQL Server) on a local **kind** cluster in WSL2 with the New Relic Kubernetes integration and APM auto-attach. No cloud subscription, no Docker Desktop, no cost: a free New Relic account covers everything except Lab 4 (New Relic AI, an Advanced Compute add-on), which has a NRQL fallback.

This kit mirrors the Dynatrace kit (`dynatrace-ai-observability-workshop`): same app, same faults, same lab order, so the two sessions can be compared feature by feature.

## Start here

1. Clone the kit into WSL (files are stored with Linux line endings, nothing to convert):

   ```bash
   git clone https://github.com/taloc0111/newrelic-ai-observability-workshop.git ~/nr-training
   ```

2. Follow the guide top to bottom: [`src/handson-guide-part1.md`](src/handson-guide-part1.md) (Steps 0-4: account, keys, cluster, app, New Relic on the cluster) then [`src/handson-guide-part2.md`](src/handson-guide-part2.md) (Labs 1-8 and appendices). The same content is in [`docs/NewRelic_AI_HandsOn_Guide.docx`](docs/NewRelic_AI_HandsOn_Guide.docx).

Every command in the guide runs inside the WSL shell and references `~/nr-training/labs/...`.

## What is in the repo

| Path | Content |
|---|---|
| `src/handson-guide-part1.md` | Steps 0-4: prerequisites, New Relic account and keys, kind cluster, build and deploy SimplCommerce, nri-bundle + Instrumentation |
| `src/handson-guide-part2.md` | Labs 1-8, appendices A-E (account defaults, free-account gates, troubleshooting, maturity ladder, reset) |
| `labs/` | Runnable scripts, manifests and NerdGraph queries, one folder per step or lab (table below) |
| `labs/lib/nerdgraph.py` | 40-line NerdGraph client (stdlib only): `python3 nerdgraph.py file.graphql key=value ...` |
| `.gitattributes` | Forces LF on `.sh`, `.yaml`, `.json`, `.graphql`, `.nrql`, `.py`, `.md`, so a Windows clone works in WSL |

The slide deck, the presenter run sheet and the build scripts that generate the `.docx`/`.pptx` are kept by the presenter and are not part of this repo.

## Lab folders

| Folder | Guide section | Content |
|---|---|---|
| `00-tools` | Step 2 | `setup-tools.sh`: Docker Engine + kind + kubectl + helm + k9s inside WSL (idempotent) |
| `01-cluster` | Step 2 | `kind-config.yaml` (cluster `nr-workshop`, nodePort 30080 to host 8080), `create-cluster.sh` |
| `02-app` | Step 3 | `Dockerfile`, `k8s/{namespace,mssql,app,loadgen}.yaml`, `build-and-deploy.sh`, `redeploy.sh` (records a deployment marker) |
| `03-newrelic` | Step 1, 4 | `save-keys.sh` (no-echo prompts, writes `~/.nr-keys`), `whoami.graphql`, `values.yaml` (nri-bundle), `instrumentation.yaml` (.NET auto-attach for `app=simplcommerce`), `install-newrelic.sh` |
| `04-alerts` | Lab 1 | `create-alert-policy.sh` + `policy.graphql`, `condition-error-rate-static.graphql` (fixed 5 %), `condition-response-time-baseline.graphql` (anomaly), `find-policy.graphql`, `list-conditions.graphql` - idempotent |
| `05-workflow` | Lab 2 | `create-workflow.sh <topic>` + `destination.graphql` (webhook ntfy.sh), `channel.graphql` + `channel-payload.json` (Handlebars payload), `workflow.graphql` (filter on the policy), `find-notifications.graphql` |
| `06-faults` | Lab 3 | `faults.sh` (mssql-down/up, 500s, throw, crashloop, imagepull + rollbacks), `verify-issues.sh` + `issues.graphql`, `record-deployment.sh` + `deployment.graphql` + `entity-guid.graphql` (change tracking) |
| `07-nrai` | Lab 4 | `prompts.md`: prompt sheet for Ask AI, Explain this error, Response Intelligence; `nrql-cheatsheet.md`: the same answers as NRQL for accounts without New Relic AI |
| `08-log-condition` | Lab 5 | `condition.nrql` + `condition-log-errors.graphql` + `create-log-condition.sh`: NRQL condition on error logs as code (idempotent) |
| `09-predictions` | Lab 6 | `predict.nrql` (NRQL `PREDICT`), `condition-predictive.graphql` + `create-predictive-condition.sh` (predictive alert, optional) |
| `10-ai-monitoring` | Lab 7 | `app.py`, `Dockerfile` (`newrelic-admin run-program`), `requirements.txt`, `k8s.yaml`, `run-demo.sh` (`--ollama` for the free in-cluster model), `ask.sh "question"` (recorded free-form prompt), `ollama.yaml` + `setup-ollama.sh` |
| `11-mcp` | Lab 8 | `README.md` + `mcp.json` for Ground Truth, the New Relic MCP server (GA, OAuth; no key in the file) |

## Lab order and timing

Labs are numbered in the order you would build this for real, and each one prepares the next:

1. **Lab 1** - alerting as code: fixed 5 % error-rate condition (fires in Lab 3) and a baseline condition (learns for later) (5 min)
2. **Lab 2** - Workflow: destination + channel + workflow to an ntfy push, proven with a 500s burst (7 min)
3. **Lab 3** - Incident Intelligence: stop SQL Server, watch incidents correlate into one issue with context, roll back, watch it close itself (15 min)
4. **Lab 4** - New Relic AI: Ask AI to NRQL, Explain this error, Response Intelligence - and how to read what it generates (8 min; NRQL fallback on free accounts)
5. **Lab 5** - detection as code: NRQL condition on error logs, prove it fires and correlates (5 min)
6. **Lab 6** - NRQL Predictions and predictive alerting (homework: needs a few hours of traffic)
7. **Lab 7** - AI Monitoring for an LLM service (optional). Stack: FastAPI + OpenAI Python SDK against an OpenAI-compatible endpoint - by default **Ollama + qwen2.5:0.5b** inside the cluster (free, no key) - instrumented by the **New Relic Python agent** (AI Monitoring), read in the **AI Monitoring** UI
8. **Lab 8** - Ground Truth (the New Relic MCP server, GA) from your IDE agent (talk track: needs the MCP Server switch in Feature Control, which the course account does not offer)

Timings measured on the clean run (2026-11-14): Kubernetes events within a minute; a 150 s burst of errors opens alert events about 3 minutes in and the merged issue + push about 30 s later; when the database outage kills the app (it does, within about a minute), the error-rate condition opens a "Signal lost" event 3 minutes after the last transaction (~T+4:30) and the push follows a minute later; alert events close as soon as the signal recovers, or by loss of signal 3-4 minutes after the last data point. "Incident" is now called "alert event" in the New Relic UI; NerdGraph keeps the old names.

Three short UI-only items were added after the rehearsal and need no kit files: **Alert Coverage Gaps** (Lab 1) and **Compound alerts** (Lab 5) are exercises; **Performance Risks** (Lab 4) is a talk-track item, because the course account reports "Not eligible" for it.

## Talking to the Lab 7 model

```bash
bash ~/nr-training/labs/10-ai-monitoring/ask.sh "your question"
```

The question goes through the instrumented `ai-descgen` service, so it appears in New Relic (APM -> ai-descgen -> AI Traces, and as a span in the transaction trace) with prompt, answer and tokens.

## Secrets

Two New Relic keys are used: the **license key** (ingest; nri-bundle, agent injection, the Lab 7 pod - stored in `~/.nr-keys` by `save-keys.sh`, chmod 600, and in Kubernetes Secrets) and a **User key** (`NRAK-`; NerdGraph for Labs 1, 2, 3, 5, 6 and the MCP server in Lab 8 - `~/.nr-keys` only). Never commit them, paste them into chat or put them in a notes file. The SQL Server password in `labs/02-app/k8s/app.yaml` is a throwaway demo value for the local cluster.
