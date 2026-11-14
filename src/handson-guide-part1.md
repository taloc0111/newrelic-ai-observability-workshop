# New Relic AI-Powered Observability - Hands-On Guide

Demo app **SimplCommerce** (.NET 8 + SQL Server) on a local **kind** cluster in WSL2, instrumented by the **New Relic Kubernetes integration** (nri-bundle) and **APM auto-attach** (k8s-agents-operator). No cloud, no Docker Desktop, no cost: a free New Relic account (100 GB/month, one full platform user) covers Steps 0-4 and Labs 1, 2, 3, 5, 6, 7. Lab 4 (New Relic AI) needs an account with the Advanced Compute add-on; the guide gives the NRQL fallback.

Follow the steps top to bottom. Every command runs **inside the WSL shell**.

## Table of contents

- Step 0 - Prerequisites
- Step 1 - Account and keys
- Step 2 - Local Kubernetes cluster
- Step 3 - Build and deploy SimplCommerce
- Step 4 - New Relic on the cluster
- Lab 1 - Alerting as code: fixed threshold and baseline
- Lab 2 - Workflow: issue to push notification
- Lab 3 - Incident Intelligence: fault, correlate, explain, auto-close
- Lab 4 - New Relic AI
- Lab 5 - Detection as code: NRQL condition on logs
- Lab 6 - NRQL Predictions (homework)
- Lab 7 - AI Monitoring (optional)
- Lab 8 - AI MCP Server (optional)
- Appendices A-E

## What you will build

![Figure 1 - The demo environment.](assets/fig-demo-environment.png)

Signals are collected with no code change (agent injection, Kubernetes integration, Fluent Bit), land in NRDB as events with their entity relationships, and the AI layer sits on top: NRQL conditions and baselines raise incidents, Incident Intelligence correlates them into one issue, New Relic AI answers in natural language, Workflows turn issues into actions.

![Figure 2 - How New Relic AI runs.](assets/fig-newrelic-ai-architecture.png)

The labs push one fault through the whole picture, in the order you would build it for real: conditions first, then routing, then the outage and its issue, then the AI that explains it.

![Figure 3 - One outage, end to end: what you see, on which screen, and when.](assets/fig-course-lab-flow.png)

## Step 0 - Prerequisites

| You need | Check |
|---|---|
| Windows 10/11 with WSL2 + Ubuntu | `wsl -l -v` shows VERSION 2. Missing: `wsl --install -d Ubuntu`, reboot |
| 8 GB or more RAM for WSL2 (10 GB if you run Lab 7 with Ollama) | `wsl -e free -g`. Raise in `%UserProfile%\.wslconfig`: `[wsl2]` `memory=10GB`, then `wsl --shutdown` |
| git in WSL | `wsl -e git --version` |
| Access to the two repos: the lab kit https://dev.azure.com/loctad/application/_git/newrelic-ai-observability-workshop and the demo app https://dev.azure.com/loctad/application/_git/SimplCommerce | open both once in the browser (sign in) |

Clone the lab kit into WSL (the scripts are stored with Linux line endings, nothing to convert):

```bash
git clone https://dev.azure.com/loctad/application/_git/newrelic-ai-observability-workshop ~/nr-training
ls ~/nr-training/labs      # 00-tools ... 11-mcp
```

Do not install Docker Desktop; Step 2 installs Docker Engine and the tools.

## Step 1 - Account and keys

1. Sign up at https://newrelic.com/signup (free tier: 100 GB/month, 1 full platform user, no card). Pick the data region (US or EU) and remember it: EU accounts use `one.eu.newrelic.com`, `api.eu.newrelic.com` and the collector `collector.eu01.nr-data.net`.
2. **Account id**: top right, account menu, or in any URL after `accounts/`. Digits only.
3. **License key** (ingest): avatar, **API keys**, the key of type *INGEST - LICENSE* (40 characters, ends in `NRAL`). This goes into the cluster: nri-bundle, agent injection, the Lab 7 pod.
4. **User key**: same page, **Create a key**, type *User*, name `nr-workshop-user`. Starts with `NRAK-`. This is the control plane: NerdGraph for policies, conditions, workflows, issues, change tracking, and the MCP server in Lab 8.
5. Store them (no-echo prompts, chmod 600) and check:

```bash
bash ~/nr-training/labs/03-newrelic/save-keys.sh
source ~/.nr-keys
python3 ~/nr-training/labs/lib/nerdgraph.py ~/nr-training/labs/03-newrelic/whoami.graphql   # your email + account id
```

> Keys are secrets: only in `~/.nr-keys` and in Kubernetes Secrets. Never in chat, notes or the repo. Two keys, not one: the license key can only write data, the User key can change the account; keeping them apart keeps the cluster least-privilege. Name the User key with the `nr-workshop-` prefix so cleanup is one filter.

New Relic AI (Lab 4) is a paid capability: on a free account the **Ask AI** button is absent. Decide now whether you demo it on a paid account or run the NRQL fallback.

## Step 2 - Local Kubernetes cluster

```bash
bash ~/nr-training/labs/00-tools/setup-tools.sh      # Docker Engine, kind, kubectl, helm, k9s (idempotent; reopen the shell if Docker was just installed)
bash ~/nr-training/labs/01-cluster/create-cluster.sh
kubectl get nodes                                    # nr-workshop-control-plane Ready
```

Open **k9s** in a second WSL terminal and keep it open: it is your live view and it keeps the WSL VM alive (WSL2 stops the VM when the last shell exits). Port 8080 on Windows maps to nodePort 30080 in the cluster.

## Step 3 - Build and deploy SimplCommerce

First build 10-20 minutes.

```bash
bash ~/nr-training/labs/02-app/build-and-deploy.sh v1
curl -is http://localhost:8080/health | head -1                                       # HTTP/1.1 200 OK
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/demo/status/500    # 500 = fault endpoints on
kubectl -n simplcommerce logs deploy/loadgen --tail=3                                 # GET /... -> 200 every 2 s
```

What the script does: clones the repo into `~/src`, builds the image, `kind load`s it (kind cannot see the host Docker cache), applies namespace, mssql, app and load generator. The app pod runs an initContainer that creates the database and applies the EF migration script; the app reads its configuration from the database at boot - remember that for Lab 3.

Open http://localhost:8080 in Windows. The seed ships 26 products. Admin (`/Admin`, `admin@simplcommerce.com` / `1qazZAQ!`) is optional.

## Step 4 - New Relic on the cluster

```bash
bash ~/nr-training/labs/03-newrelic/install-newrelic.sh
kubectl -n newrelic get pods          # infrastructure (kubelet, ksm, control-plane), kube-events, logging, k8s-agents-operator: Running
kubectl -n newrelic get instrumentation
```

The script installs **nri-bundle** with `values.yaml` (infrastructure, Kubernetes events, Fluent Bit logging, kube-state-metrics, metadata injection, the k8s-agents-operator; the license key is passed with `--set`, never written to the file), applies the **Instrumentation** CR for `app=simplcommerce` in namespace `simplcommerce` and restarts the app so the .NET agent is injected at pod start; it prints the proof (an init container with `newrelic` in its name, env `CORECLR_PROFILER` and `NEW_RELIC_APP_NAME=SimplCommerce`).

Design choices: agent injection by label selector (the only mode on kind that needs no image change; identical to production for transactions, traces, DB calls and errors), Fluent Bit tailing pod stdout (Log events with `namespace_name`, `pod_name`), kube events (BackOff, Unhealthy on the Issue timeline). Low data mode is **off** so the labs see logs and events; a shared or free account under pressure flips it on in `values.yaml`.

Check after ~3-5 minutes of traffic: **APM & Services** shows `SimplCommerce` with throughput and a **Databases** tab (SQL Server queries); **Kubernetes** shows cluster `nr-workshop`, namespace `simplcommerce`, pods and the app entity linked to its pod; **Logs** filtered on `namespace_name:"simplcommerce"` shows the .NET console lines; a **Distributed trace** of a storefront request shows the SQL spans. No APM entity despite traffic: `kubectl -n simplcommerce rollout restart deployment/simplcommerce` and check the init container ran (`kubectl -n simplcommerce describe pod -l app=simplcommerce`).

Free-tier budget: this cluster ingests roughly 1-3 GB/day with logs on (check **Administration -> Data management**). The 100 GB/month is safe for a workshop week; leave the cluster off overnight when you do not need Lab 6 history.
