## The labs

Run them in order; each one prepares the next. Session timing for a 40-minute slot: Lab 1 (5) - Lab 2 (7) - Lab 3 (15) - Lab 4 (8) - Lab 5 (5). Labs 6, 7 and 8 are homework. Timings measured in the rehearsal (2026-11-07): a static NRQL condition on a 60 s event timer opens an **alert event** about 3 minutes after the fault, the issue is ACTIVATED and the push arrives about a minute later; Kubernetes events arrive within a minute; alert events close as soon as the signal recovers, or by loss of signal 3-4 minutes after the last matching data point. Vocabulary: New Relic renamed "incidents" to **alert events** in the UI in 2026 (one per condition and signal); an **issue** groups alert events and is what gets routed. NerdGraph still uses the old names (`NrAiIncident`, `incidentIds`).

## Lab 1 - Alerting as code: fixed threshold and baseline

Goal: see the two generations of detection New Relic offers on day one, and create them from a script so they can live in a repo. Kit: `labs/04-alerts`.

```bash
bash ~/nr-training/labs/04-alerts/create-alert-policy.sh      # idempotent: policy nr-workshop + 2 conditions
```

Open **Alerts**, **Alert conditions (policies)**, `nr-workshop`. **First, one click the script cannot do**: policy **Settings**, tick **Correlate and suppress noise**, Save. A policy created through NerdGraph has it off, and without it Incident Intelligence never merges alert events into one issue: Lab 3 and Lab 5 would show two issues and two pushes instead of one. (Rehearsal 2026-11-15: forgot the tick, got two uncorrelated issues; the fix does not merge issues that are already open, only the next ones.)

![Figure 5 - Policy nr-workshop, Settings: Correlate and suppress noise ticked; issue creation preference stays "One issue per condition and signal".](assets/screens/lab1-policy-correlate.png)

1. **Gen 2, fixed threshold** - `SimplCommerce error rate > 5%`: NRQL `percentage(count(*), WHERE error IS true) FROM Transaction`, signal 60 s window evaluated on an **event timer**, critical above 5 for 1 minute, and a **loss of signal** rule: no data for 3 minutes opens an alert event ("the app stopped reporting") and data coming back closes it. This is what fires in Lab 3 and on `faults.sh 500s`.
2. **Gen 1, baseline (anomaly)** - `SimplCommerce response time anomaly`: same signal settings, direction upper only, threshold 3 standard deviations for 5 minutes. The chart shows the learned band growing as history arrives. It learns faster than you expect on steady load-generator traffic: in the rehearsal it opened its first WARNING issue about 5 hours after creation, on a 3x response-time blip that lasted 5 minutes, and closed it 5 minutes later.
3. Open the fixed condition, **View as code**: the NRQL and the terms the script sent. Exercise: change the threshold to 10 in the UI, Save, rerun the script - it reports "condition exists" and leaves your change; delete the condition and rerun to recreate it.

Notice:

- A **policy** groups conditions and is what the workflow filters on; `PER_CONDITION_AND_TARGET` gives one issue per condition per entity, so Lab 3 shows distinct symptoms before correlation.
- Without the fixed condition nothing opens in Lab 3 on day one: the baseline has no history yet and the Kubernetes integration raises **events**, not alert events, unless you add conditions on `K8sContainerSample` (Lab 5 shows how). Compare with Dynatrace, where Kubernetes detectors are on by default.
- **Alert Coverage Gaps** (Alerts -> Alert Coverage Gaps, Beta): the APM services that report data but have no condition, with throughput and error rate, a coverage percentage, and a **Recommend alert conditions** button (select up to 20 entities). It looks at APM entities only, not at pods, the cluster or SQL Server. Rehearsal: after Lab 1 and Lab 7 it showed "2 entities, 50 % covered" with `ai-descgen` as the gap. Ask AI's answer to "write me an alert condition" (Lab 4, prompt 6) comes from the same recommendation engine.
- Same objects, three ways: the UI form, this NerdGraph script, or Terraform (`newrelic_alert_policy`, `newrelic_nrql_alert_condition` - see the 2025 `newrelic - terraform - aiops` folder for a worked example).

## Lab 2 - Workflow: issue to push notification

Goal: route issues to people before the outage, so the push arrives during Lab 3. Kit: `labs/05-workflow`.

New Relic splits routing into three objects, created in this order by the script: **destination** (where: a webhook to `https://ntfy.sh`), **channel** (what: a Handlebars payload template over the issue), **workflow** (when: a filter on the Lab 1 policy id, triggers ACTIVATED and CLOSED).

```bash
bash ~/nr-training/labs/05-workflow/create-workflow.sh nr-workshop-$RANDOM   # prints the ntfy topic
```

Subscribe on your phone or a browser tab: `https://ntfy.sh/<topic>`. Quick proof without an outage:

```bash
bash ~/nr-training/labs/06-faults/faults.sh 500s      # 150 s of 500s -> error rate 5 %+ -> alert event ~+3:00 -> issue + push ~+4:00 -> CLOSED ~4 min after the burst ends
```

Expect: **Alerts -> Issues & activity** shows the issue `SimplCommerce error rate > 5%` on entity SimplCommerce; the ntfy page shows the push with priority, title, issue id and the issue URL; a few minutes after the burst a second push `CLOSED`. Open **Alerts -> Workflows -> nr-workshop-ntfy**: filter, channel, **Test workflow** button (sends a synthetic issue - useful before a real fault).

Notice:

- The workflow sees **issues**, not alert events: once Lab 5 exists, one `500s` burst opens two alert events (error rate and error logs) and Incident Intelligence merges them into **one** issue, one push (verified in the rehearsal). Lab 3 shows the correlation; this is where New Relic dedupes for you and why routing should key on issue id.
- Debugging a push that never arrives: `SELECT trigger, status, payload FROM NrAiNotification SINCE 1 hour ago` shows every delivery attempt with the rendered payload. In the rehearsal the first channel template produced invalid JSON (unescaped quotes from `{{ json entitiesData.names }}`), ntfy rejected it, and `status` said `FAIL`.
- Free accounts can send email and webhooks; Slack, PagerDuty, ServiceNow and Jira destinations also exist and are configured the same way (destination + channel).
- Autonomy ladder = notify, ticket, remediate with approval, self-heal. New Relic Workflows do not run code; the "act" step is the webhook target (an Azure Function, a GitHub Action, a runbook tool) - keep the human approval there.

## Lab 3 - Incident Intelligence: fault, correlate, explain, auto-close

Goal: one fault, watch New Relic turn several signals into one issue with context, then close it itself. Kit: `labs/06-faults`.

```bash
bash ~/nr-training/labs/06-faults/faults.sh mssql-down
```

What happens (watch k9s): within about a minute a background job inside SimplCommerce hits an unhandled `SqlException` and the .NET host exits - the load generator sees one HTTP 500 and then connection refused - and the container cannot boot again because it reads its configuration from the database: CrashLoopBackOff. From then on there are **no transactions at all**: the app is not slow or erroring, it is gone. (Read the log line yourself: `Unhandled exception. Microsoft.Data.SqlClient.SqlException ... Could not open a connection to SQL Server`.)

Timeline measured on the clean run (fault at T+0, 2026-11-14): T+0:35 Kubernetes `Unhealthy`, T+1:25 `BackOff` (Kubernetes UI, Issue timeline) - events, nobody is told; T+4:30 the error-rate signal has been absent for 3 minutes, so the Lab 1 condition's loss-of-signal setting opens **"Signal lost for 3 minutes on 'SimplCommerce error rate > 5%'"**; T+5:30 the issue is ACTIVATED with that one alert event and the phone gets **one** push. Silence is the only signal a dead dependency leaves, and only that setting turns it into an alert. If the app happens to survive a minute or two (it did in one run), the error-rate and error-log events open first and the signal-lost event joins the same issue - a bonus, not the plan. The deterministic "many signals, one issue" demo is the `500s` burst in Lab 2 and the `throw` burst in Lab 5.

Two settings make this work, both in `labs/04-alerts/condition-error-rate-static.graphql` and `labs/08-log-condition/condition-log-errors.graphql`: `aggregationMethod: EVENT_TIMER` (evaluate on the clock; with EVENT_FLOW a burst followed by silence is never evaluated, and in the first rehearsal run the error-rate condition did not fire at all) and `expiration` (loss of signal, 3 min on the error-rate condition with `openViolationOnExpiration: true`, because "no transactions" is the outage; 4 min on the log condition; `closeViolationsOnExpiration: true` on both, so they close themselves when data is back). `labs/02-app/k8s/app.yaml` also relaxes the probes (`failureThreshold` 18/10) so Kubernetes does not pull the pod out of the Service before the app itself gives up; how long the app survives is decided by its own background job, not by the probes.

1. **Alerts -> Issues & activity**. Open the issue: **Issue summary** (priority, when, entity SimplCommerce), **Alert events** tab (usually one row, "Signal lost for 3 minutes"; if the app survived long enough to error, the error-rate and error-log rows sit above it - the UI renamed "incidents" to "alert events" in 2026, NerdGraph still says `NrAiIncident`), **Timeline** with Kubernetes events and deployment markers, **Related entities** (the app, its pod, the cluster). **Alerts -> Decisions** lists the global correlation rules; the one that fired here is "Same New Relic Target ID" (same entity GUID), which is why Lab 5 facets its query by `entity.guid`. Correlation only runs for policies with **Correlate and suppress noise** ticked (policy -> Settings); a policy created by NerdGraph has it off.
2. **Why there is no root cause**: open the **Potential causes** tab (and the AI summary when Advanced Compute is on). Expect nothing that names SQL Server. The app process died before any request reached the agent, so APM recorded no `SqlException` - the only `TransactionError` rows are the HTTP 500s from Lab 2 - and there is no error class for the issue to show. The exception exists only as a container log line: **Logs**, query `namespace_name = 'simplcommerce' AND message LIKE '%SqlException%'` (`Unhandled exception. Microsoft.Data.SqlClient.SqlException ... Could not open a connection to SQL Server`). That is the Fluent Bit copy, no entity, so it is not linked to the issue. No agent in the SQL Server pod, no signal, no root cause: the same blind spot Dynatrace has in this scenario. An AI can only point where there is data.
3. **Errors inbox** (APM -> SimplCommerce -> Errors): the exceptions grouped, with stack traces. **Explain this error** is Lab 4.
4. **Kubernetes -> nr-workshop -> simplcommerce**: pod red, container restarts climbing, events. There is no issue for it unless a condition exists (Lab 5 exercise: `SELECT max(restartCount) FROM K8sContainerSample WHERE namespaceName = 'simplcommerce' FACET podName`).
5. Roll back, touch nothing in New Relic:

```bash
bash ~/nr-training/labs/06-faults/faults.sh mssql-up          # scale back, restart app, wait for Ready
bash ~/nr-training/labs/06-faults/record-deployment.sh v1-rollback "mssql restored"   # marker on the Issue timeline
bash ~/nr-training/labs/06-faults/verify-issues.sh ALL        # a few minutes later: CLOSED
```

Clean run: app Ready about 1 minute after `mssql-up`, the signal-lost event closed once transactions were back (EVALUATOR), the issue CLOSED and the phone got one CLOSED push about 3 minutes after the rollback. Keep the Lab 6 predictive condition disabled until Lab 6: it reacts to the 15 minutes of zero traffic with a "Predicted: < 10" event that merges into this issue and holds it open.

6. Notice: **CLOSED = the signal at that condition recovered (or the loss-of-signal timer ran out), not "system healthy"**. In the first rehearsal run, before the loss-of-signal settings existed, every issue had closed itself 7 minutes into a 15-minute outage because the crash-looping app simply stopped producing the signals the conditions watched. Check the app yourself: `curl -is http://localhost:8080/health | head -1`.

Without the Lab 1 condition: Kubernetes events only, no incident, no issue, no push. Same fault, nothing routed. The condition is what wires the app into Incident Intelligence.

Other faults in `faults.sh`: `500s` (clean 5xx burst, app stays up), `throw` (exceptions with stack traces, used in Labs 4 and 5), `crashloop` / `imagepull` with their `rollback-*` (restart loop vs never-ready: different Kubernetes events, same lesson - alert on what you can see).

## Lab 4 - New Relic AI

Goal: natural language in, NRQL out - and learn to read what comes out. Kit: `labs/07-nrai/prompts.md` (prompts), `labs/07-nrai/nrql-cheatsheet.md` (the NRQL to run by hand on an account without New Relic AI).

New Relic AI is GA (June 2025) and billed as **Advanced Compute**. On a free account the **Ask AI** button is still there but the panel says **"Ask AI - Offline: Ask AI requires the Advanced Compute add-on"** with a *Get access* link (and, next to it, **Autopilot** in public preview at no cost, with its own *Get access*). Two places switch it on, both as the account owner/admin:

1. **Administration -> Feature Control -> New Relic AI -> Activate** (the Feature Control Manager; the page warns "we start billing for usage as soon as you activate a feature"). On the course account this reads *On for all accounts*, and Ask AI is online.
2. **Administration -> Previews & Trials -> Trials -> "Advanced Compute - 30 Day Trial"** (status *Available* until started) - see Figure 4 in Step 1, taken before activation: 30 days of Advanced Compute at no cost - the right choice for a workshop account that is otherwise free. Start it a day or two before the session, not on the day.

Check **Administration -> Consumption Management -> Advanced Compute Bundle** afterwards: usage shows up there (on the course account as non-billable; about 0.1 CCU per prompt). If neither switch is available to you, the cheat sheet reproduces every answer as NRQL so the lab works on a free account; the talking points are the same.

1. Any page, **Ask AI** (top right). Prompt: `Show error logs from the Kubernetes namespace simplcommerce in the last hour`. Open the generated NRQL (**Open in query builder**). Expect `FROM Log WHERE namespace_name = 'simplcommerce' AND level = 'ERROR'` or similar. Check the attribute names against the Logs UI: in the rehearsal the model wrote `namespace = 'simplcommerce'` and reported "No logs found"; `namespace_name` returns hundreds of lines. The .NET `fail:` lines have no `level`, so add `OR message LIKE '%fail:%'` and compare counts. The follow-up `count them per 5 minutes as a chart` kept the context but filtered on `error.class IS NOT NULL`, an attribute the pod logs do not carry: a flat zero chart. `labs/07-nrai/prompts.md` records what each prompt produced.
2. Same conversation: `count them per 5 minutes as a chart`. The chat is stateful and should add `TIMESERIES 5 minutes`; if it switches to another event type, the context was lost. Write self-contained prompts anyway.
3. `Which transactions of SimplCommerce had the highest error rate in the last 2 hours?`: expect `/api/demo/throw` on top. In the rehearsal the model queried **`TransactionError`** and answered "`WebTransaction/StatusCode/500` = 0 %" two hours after an outage: `TransactionError` rows have no `error` attribute, so the percentage is 0 by construction. Run cheat sheet query 3 on `Transaction` next to it.
4. `Show open issues and which condition opened each`: rehearsal answer was `FROM NrAiIncident SELECT count(*) FACET conditionName WHERE event = 'open' SINCE 1 hour ago` - a count of alert-event **openings in the last hour** (3, 2, 1) while **zero** issues were open. Compare with **Issues & activity**; same words, different question.
5. A vague prompt, `what is wrong with SimplCommerce right now`: rehearsal answer was the latest `TransactionError` message ("Demo 500 - injected unhandled exception"). Fair, but "latest error" is not "what is wrong" - it says the same on a healthy day. Name the entity type and the signal you mean: `open issues on the APM application SimplCommerce`.
6. `Write an NRQL alert condition that fires when SimplCommerce error rate is above 5 percent for one minute`: no NRQL comes back; NRAI calls its **alert recommendations** tool and offers three conditions for the entity (response time, throughput, error rate) with an **Add alerts** button - the same engine as Alert Coverage Gaps in Lab 1. Compare the error-rate one with `labs/04-alerts/condition-error-rate-static.graphql`: window, aggregation method, loss of signal. The script is the reviewed answer.
7. **Explain this error**, two doors: **Triage Inbox (Errors inbox)** -> the `/api/demo/throw` group -> **Stack trace** -> Explain this error; or **APM -> SimplCommerce -> Logs** -> click an `ERROR` line -> the **Explain this error** button on the log details. Rehearsal: a correct one-paragraph reading ("a demo fault intentionally triggered") and five generic next steps with links to Microsoft and New Relic docs. Derived from the message and stack trace, not from the Kubernetes events. Follow up with `how do I reproduce it locally?`.
8. **Issue page**, the Lab 3 issue (3 alert events): the **AI summary** (Response Intelligence, preview) has three panels. *What's impacted* read all three alert events and the entity tags and quoted real numbers ("post-alert mean 0.1 compared to a baseline mean of 0.03"). *What happened previously* is empty until you link retrospectives (Knowledge). *What to check*: the first card said "**Rollback Deployment** - revert v1-rollback of SimplCommerce to the previous stable version" - that marker is the fix we recorded after `mssql-up`; the model inferred cause from proximity. Nothing says "the SQL Server pod was scaled to 0": no agent in that pod, no signal. Open the **Potential causes** tab next to Overview.
9. **Performance Risks** (APM -> SimplCommerce -> Performance Risks, or Triage Inbox -> Performance Risks; GA Oct 2026): the scanner lists N+1 queries, sequential database calls and large payloads found in the traces, with an AI explanation per finding - detection without a condition, a problem found before it is an outage. On the course account the page says **"Not eligible - your account is not currently eligible for this feature"** (2026-11-07), so this is a talk-track item; open it on your own account to see whether SimplCommerce's catalog pages show up.
10. **Query builder**: paste `labs/08-log-condition/condition.nrql` and use **Explain**: NRQL to English, and it reads the comments, so comment your conditions.

Notice: a wrong query can return a plausible answer - in the rehearsal, 3 of the first 3 generated queries were wrong (attribute, filter, event type) and two of them painted "no errors" right after an outage. Compare with Issues & activity or APM Summary before quoting a number. The useful part is the draft and the list of event types it considered. NRAI runs with your permissions, prompts do not train the model, and each answer costs Advanced Compute units (Administration -> Consumption Management shows how many).

## Lab 5 - Detection as code: NRQL condition on logs

Goal: gen 3 - alert on anything you can express as a NRQL query. Kit: `labs/08-log-condition`.

```bash
bash ~/nr-training/labs/08-log-condition/create-log-condition.sh     # idempotent (by condition name), attaches to policy nr-workshop
```

Open **Alerts -> Alert conditions -> nr-workshop -> simplcommerce error-log spike**: the chart shows the log-count series against the threshold (5 per minute). Query: `labs/08-log-condition/condition.nrql` - the .NET agent's logs-in-context (`entity.name = 'SimplCommerce' AND level = 'ERROR'`, `FACET entity.guid`); signal 60 s on an event timer; critical above 5 for one window; loss of signal closes the event after 4 minutes of silence.

Prove it fires:

```bash
bash ~/nr-training/labs/06-faults/faults.sh throw      # 30 exceptions = 60 fail: lines in 60 s
```

Expect (rehearsal, 150 s burst): the alert events `simplcommerce error-log spike` and `SimplCommerce error rate > 5%` (Lab 1) open about 2.5-3 minutes after the burst starts, the compound alert a few seconds later, and Incident Intelligence **merges the first two into one issue** on entity SimplCommerce (`Contains: 2 events`; **Alerts -> Decisions** -> "Same New Relic Target ID" is the rule that matched); the compound condition opens its own issue. One push for the merged issue about 4 minutes in. The error-rate event closes as soon as the rate drops, the log event by loss of signal 4 minutes after the last error line, and the issue closes with it - about 4 minutes after the burst ends. A burst shorter than 2 minutes closes before the issue activates and nothing merges.

![Figure 6 - The merged issue (clean run 2026-11-15): Alert events (2) - error rate and error-log spike - under one issue on SimplCommerce. The AI summary reads the error rate correctly but "What to check" recommends database work, although the fault was an injected exception: plausible, wrong, review before you quote it.](assets/screens/lab5-issue-merged.png)

Notice:

- **Run the NRQL in the Query builder first** with `TIMESERIES 1 minute`: if the chart is empty the attribute names are wrong, and the condition would never fire with no error in the UI.
- **Two copies of every log line, with different attributes.** The same `fail:` lines arrive twice: once from the agent (logs-in-context, `newrelic.source = 'logs.APM'`, with `level` and `entity.guid`) and once from Fluent Bit (`namespace_name`, `pod_name`, `container_name`, **no `level`**). The commented query in `condition.nrql` shows the Fluent Bit version: it needs `message LIKE '%fail:%'`, and an issue built on it lands on "Log query" with no entity, so nothing can correlate it. Compare the two charts; that is the whole reason the condition facets by `entity.guid`.
- **Timer, not flow, for sparse data.** Error logs come in bursts; `EVENT_FLOW` only evaluates a window after later events arrive, so a burst followed by silence is never evaluated (first rehearsal run: no issue at all). `EVENT_TIMER` evaluates on the clock. And `count(*)` never reports 0 on its own, so only the condition's **loss of signal** setting (`expiration`, 5 min) closes the event; gap filling does not.
- Wait about 5 minutes after creating the condition before you fire the fault; a condition created seconds before the burst missed it in the rehearsal.
- Same mechanism for Kubernetes: `SELECT max(restartCount) FROM K8sContainerSample WHERE namespaceName = 'simplcommerce' FACET podName`, above 3, is the "built-in Kubernetes detector" New Relic does not ship by default.

Exercise, 3 minutes, UI only - **Compound alert** (Alerts -> Compound Alerts -> Create a compound alert condition): name `SimplCommerce compound: errors + error logs`, then pick `SimplCommerce error rate > 5%` and `simplcommerce error-log spike` (the form labels them `A` and `B`), expression **`A AND B`** - the aliases are mandatory, a bare `AND` fails with "trigger expression is missing aliases" - threshold duration 1 minute, policy `nr-workshop`, Save. On the next `throw` burst it opens its own issue titled "Compound alert: SimplCommerce compound: errors + error logs" and its own push, and closes once either component closes. A compound condition opens one alert event only when the expression over up to five ordinary conditions is true; the components can be silenced so only the compound one notifies. Put it next to what you just saw: Decisions is the AI merging issues after they open; a compound alert is you declaring the combination up front - deterministic, no learning, no CCU. Use it where you know the pattern, leave Decisions for the ones you do not.

Prove the compound alert (wait until the previous issues are CLOSED first, or the new events join the old issue):

```bash
bash ~/nr-training/labs/06-faults/verify-issues.sh ALL   # until total: 0 or every issue CLOSED
bash ~/nr-training/labs/06-faults/faults.sh throw        # 150 s
bash ~/nr-training/labs/06-faults/verify-issues.sh       # 3-4 minutes later
```

Expect two ACTIVATED issues: the merged one on SimplCommerce (`incidents: 2`) and `Compound alert: SimplCommerce compound: errors + error logs` (`incidents: 1`), and two pushes (clean run 2026-11-14: merged issue at +2:50, compound at +4:00). When the burst ends the error-rate event closes first, which makes `A AND B` false, so the compound issue closes before the merged one; `verify-issues.sh ALL` shows both CLOSED about 4-7 minutes after the last error, with two CLOSED pushes.

## Lab 6 - NRQL Predictions (homework)

Needs a few hours of load-generator history (3-4 hours is enough). Kit: `labs/09-predictions`.

1. **Query your data**, paste `predict.nrql` (request count per 5 minutes, 6 hours, `PREDICT`), Run. The chart extends with the forecast and a confidence band; hover the dashed part.
2. Variants in the same file: `PREDICT BY 2 hours USING 12 hours` (look further, train longer - the clause order is `BY` then `USING`, the other way round is a syntax error) and a capacity trend on SQL Server memory (`K8sContainerSample`, 1-hour buckets, 2 days ahead). History plus forecast must stay under 366 buckets: `TIMESERIES 10 minutes ... PREDICT BY 7 days` is 1,152 and is rejected, so widen the bucket when you look further out. Only Holt-Winters is available (`PREDICT holtwinters(seasonality: AUTO, alpha: 0.2)` to tune it).
3. **Predictive alerting**: the docs say to enable **Predictive Alerts** under **Administration -> Previews & Trials** first; on the course account that page listed no such preview (only Response Intelligence) and the predictive condition worked without it, so check the page and move on if it is not there. Then open the Lab 1 fixed condition, **Edit**, enable **Predict future behavior** (predict by 1 hour) - the condition opens an alert event when the forecast is expected to cross the threshold. As code: `create-predictive-condition.sh` creates `SimplCommerce throughput predicted low` (static condition with `prediction: { predictBy: 3600 }` on the term; NerdGraph accepted it in the rehearsal). Constraints: static thresholds only; look-ahead between 2x and 360x the window. Create or enable it only after Lab 3: in the rehearsal it reacted to the outage's 15 minutes of zero traffic with a "Predicted: < 10" event dated an hour ahead, which merged into the Lab 3 issue and kept it open.
4. Prove it: `kubectl -n simplcommerce scale deploy/loadgen --replicas=0`, watch the throughput chart and forecast dive, then scale back to 1. The health-check traffic (~6 requests/min) keeps the signal alive, so the condition sees a real drop rather than a loss of signal. Rehearsal: the alert event opened 5 min 48 s after the scale-down as a **plain static breach** ("query result is < 10.0 for 5 minutes"), not as a predicted one - a step change has no trend for Holt-Winters to extrapolate, so the prediction cannot run ahead of it. That is the honest lesson of the lab: predictive alerting buys time on **gradual** trends (memory growth, a slow traffic decay, disk filling up), not on outages. For a visible prediction, point the condition at a series that drifts, for example SQL Server memory from `predict.nrql`.

Billing: `PREDICT` queries and predictive alerts are available on every plan; on Core Compute plans they consume Core CCUs, never Advanced Compute. Check Administration -> Consumption Management after running them.

## Lab 7 - AI Monitoring (optional)

Optional module: observability *for* AI - every LLM call recorded with model, tokens, latency, prompt and response. Kit: `labs/10-ai-monitoring`.

Stack used: **FastAPI + uvicorn** (the toy service `ai-descgen`), the official **OpenAI Python SDK** pointed at an OpenAI-compatible `/v1` endpoint, **Ollama** running `qwen2.5:0.5b` inside the kind cluster as that endpoint (free, no key), the **New Relic Python agent** (`newrelic-admin run-program`, `NEW_RELIC_AI_MONITORING_ENABLED=true`) auto-instrumenting the OpenAI client into `LlmChatCompletionSummary` / `LlmChatCompletionMessage` events, and the **AI Monitoring** UI to read them. Ollama itself is not on New Relic's compatibility list and does not need to be: the agent instruments the OpenAI SDK (0.28+), and Ollama is just the server behind `base_url`. Any other OpenAI-compatible backend (OpenAI, Azure OpenAI, Groq, Gemini) drops in by changing `OPENAI_BASE_URL` and `MODEL`.

**LLM - pick one.** The free default is a small model running **inside the kind cluster** (no account, no key, no data leaves the laptop):

```bash
bash ~/nr-training/labs/10-ai-monitoring/setup-ollama.sh        # Ollama + qwen2.5:0.5b (~400 MB download, CPU is enough)
```

Alternatives if you have an account: OpenAI (`gpt-4o-mini`), Azure OpenAI (`OPENAI_BASE_URL=https://<resource>.openai.azure.com/openai/v1`, `MODEL=<deployment>`), Groq (`https://api.groq.com/openai/v1`, `llama-3.1-8b-instant`), Google Gemini (`https://generativelanguage.googleapis.com/v1beta/openai/`, `gemini-2.0-flash`). Set `OPENAI_BASE_URL` and `MODEL` before running and paste the key at the prompt.

```bash
bash ~/nr-training/labs/10-ai-monitoring/run-demo.sh --ollama   # free in-cluster model
# or, with your own endpoint:  MODEL=... OPENAI_BASE_URL=... bash ~/nr-training/labs/10-ai-monitoring/run-demo.sh
```

The script builds and kind-loads `ai-descgen:v1`, creates the Secret (LLM key + New Relic license key from `~/.nr-keys`), deploys the service next to SimplCommerce and calls `/describe` five times from the load-generator pod.

Expect after 1-2 minutes (rehearsal: within 150 s): **APM -> ai-descgen**, left nav section **AI Monitoring -> AI Traces**: total traces, response time, token usage per trace (p99 122 on the rehearsal), error rate, and a table with one row per call - request text, response text, completions, total tokens, model, duration - because `RECORD_CONTENT_ENABLED` is on (off by default for a reason). The same nav section holds **Model Inventory**, **LLM Evaluation** (the Oct 2026 AI Evaluation feature, already in the UI), **AI Agents** and **AI Tools**; "See full AI monitoring" opens the account-wide view; **APM -> ai-descgen -> Distributed tracing** shows the LLM span inside the `/describe` transaction. In the Query builder: `SELECT request.model, response.usage.total_tokens, duration FROM LlmChatCompletionSummary WHERE appName = 'ai-descgen'`. A NRQL condition on `sum(response.usage.total_tokens)` is the "alert on token spend" story from the deck (Lab 5 mechanism).

Try your own prompts - always through the instrumented service, so every question becomes an LLM event:

```bash
bash ~/nr-training/labs/10-ai-monitoring/ask.sh "What is an issue in New Relic? One sentence."
```

It prints the answer, the model and the token counts; 1-2 minutes later the question and answer are in **APM -> ai-descgen -> AI Traces**. The first call after the model has been idle takes ~10 s (load into RAM). A 0.5B model answers confidently and often wrongly - read the output in AI Traces, that is the point of the lab.

Troubleshooting: `kubectl -n simplcommerce logs deploy/ai-descgen --tail=50` - 401 = LLM key; connection refused = base URL; `license key invalid` / `Unable to connect to collector` = `NEW_RELIC_LICENSE_KEY` or `NEW_RELIC_HOST` (EU accounts: `collector.eu01.nr-data.net`); no `Llm*` events but transactions present = `NEW_RELIC_AI_MONITORING_ENABLED` not read (the agent prints its settings at start with `NEW_RELIC_LOG=stdout`). Ollama slow on first call = model loading; `kubectl -n simplcommerce logs deploy/ollama` shows the pull and load.

Closing line: use AI to run ops, and observability to run AI.

## Lab 8 - Ground Truth, the New Relic MCP server (talk track; needs an admin switch your account may not have)

Status: **not runnable on the course account.** The OAuth login ends in "access_denied ... Feature Control Manager", and Administration -> Feature Control on that account lists a single feature (New Relic AI) with no MCP Server row, so there is nothing to activate. Keep this section as the explanation of what the agentic pillar looks like from an IDE; run it only on an account whose Feature Control offers the MCP Server. Kit: `labs/11-mcp/README.md` and `mcp.json`. Ground Truth is the GA name (September 2026) of the AI MCP Server. Connect an MCP client to `https://mcp.newrelic.com/mcp/` (EU: `mcp.eu.newrelic.com`) over **OAuth** - the client opens a browser, you log in, no key in any file: Claude Code `claude mcp add --transport http --scope user newrelic https://mcp.newrelic.com/mcp/` then `claude mcp login newrelic` (2.1.186+; on older builds open a new session and use `/mcp` -> newrelic -> Authenticate); VS Code / Copilot copy `mcp.json` to `.vscode/mcp.json`. An API-key header still works for clients without OAuth, but only after an admin enables **API Keys** for Ground Truth, and some tools are OAuth-only. On a fresh account the login fails with **"access_denied: Your administrator has disabled access to this application"**: Ground Truth is off in **Administration -> Feature Control** until an admin switches it on (rehearsal, 2026-11-07). Then repeat the Lab 4 questions; the agent chooses the NRQL and the tools, you read them. Billing: available on every plan; most tools are metered as Core CCUs, the four that call New Relic AI as Advanced CCUs. Config rewritten from the docs on 2026-11-07, not yet exercised end to end.

## Appendix A - Fresh account defaults

On: Kubernetes, APM, Logs, Triage Inbox (Errors inbox), Performance Risks, Issues & activity, the 11 global correlation decisions, Alert Coverage Gaps, Compound alerts, Lookout (per entity), change tracking, NRQL Predictions. Off or empty: any alert condition (nothing fires until you create one), any destination or workflow (nobody is told), **Correlate and suppress noise** on a policy created through NerdGraph (tick it in the policy's Settings, or nothing merges), Predictive Alerts (Administration -> Preview & Trials), **Ground Truth / MCP server (Administration -> Feature Control; OAuth login says "access_denied" until it is on)**, Advanced Compute features (New Relic AI, Response Intelligence summaries, Autopilot, Security RX, CodeStream) unless the add-on is purchased, prompt/response capture in AI Monitoring (`RECORD_CONTENT_ENABLED` is off by default).

## Appendix B - Free account gates

| Capability | Gate | Workaround |
|---|---|---|
| New Relic AI (Ask AI, Explain this error, Response Intelligence summary) | Advanced Compute add-on - the Ask AI panel says *Offline* until an admin activates it in **Administration -> Feature Control** or starts the **Advanced Compute - 30 Day Trial** under **Administration -> Previews & Trials** | `labs/07-nrai/nrql-cheatsheet.md`; or start the 30-day trial before the session |
| Autopilot, Agentic Platform, Security RX, Workflow Automation | Advanced Compute add-on | talk track (deck slide 10) |
| Second full platform user | 1 free; Standard $10 first + $99/user | trainees follow on the presenter's screen; Basic users can run NRQL and see alerts |
| APM, Browser, Mobile UI for Basic users | user type | Core or Full Platform user |
| Data ingest above 100 GB/month | ingest stops, UI locked until next month | low data mode in `values.yaml`, loadgen off overnight |
| Retention 8 days | free default | enough for a workshop week |
| AI Monitoring prompt/response text | off by default | `NEW_RELIC_AI_MONITORING_RECORD_CONTENT_ENABLED=true` (Lab 7 manifest) |

## Appendix C - Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `\r: command not found` | CRLF from the Windows copy | `find ~/nr-training/labs -name "*.sh" -exec sed -i 's/\r$//' {} \;` |
| docker not found / daemon down | Docker Engine missing or stopped | rerun setup-tools.sh; `sudo systemctl enable --now docker` |
| kubectl "connection refused", localhost:8080 refuses | WSL2 stopped the VM | keep k9s open; `docker start nr-workshop-control-plane`, wait 1 min |
| ImagePullBackOff on the app | image not kind-loaded or tag mismatch | `kind load docker-image simplcommerce:v1 --name nr-workshop` |
| App pod stuck in Init | SQL Server not ready or migration failed | `kubectl -n simplcommerce logs <pod> -c migrate` |
| Pods Pending / mssql OOMKilled | WSL2 memory cap | .wslconfig memory=10GB, `wsl --shutdown` |
| No APM entity in New Relic | pod started before the Instrumentation CR, or no traffic | `rollout restart deployment/simplcommerce`; check the init container and `NEW_RELIC_LICENSE_KEY` env; check loadgen |
| Init container present, no data | license key wrong or region mismatch | `kubectl -n simplcommerce logs <pod> -c web | grep -i "new relic"`; EU needs `NEW_RELIC_HOST=collector.eu01.nr-data.net` in the Instrumentation env |
| `newrelic-key-secret` missing in simplcommerce | operator did not replicate the license secret | `kubectl -n simplcommerce create secret generic newrelic-key-secret --from-literal=new_relic_license_key=$NEW_RELIC_LICENSE_KEY` then restart the app |
| Instrumentation apiVersion rejected | CRD drift | `kubectl get crd instrumentations.newrelic.com -o jsonpath='{.spec.versions[?(@.storage==true)].name}'`, edit `instrumentation.yaml` |
| nri-bundle `kubelet` pods CrashLoop on kind | kubelet endpoint / control-plane scraping | set `newrelic-infrastructure.controlPlane.enabled=false` in `values.yaml`; the kubelet component is enough |
| NerdGraph `401` | wrong key type | User key `NRAK-`, not the license key; `source ~/.nr-keys` |
| NerdGraph `Argument ... has invalid value` | schema drift in a `.graphql` file | open the NerdGraph explorer (one.newrelic.com/nerdgraph-graphiql-explorer), paste the mutation, fix the field |
| Condition never fires, chart empty | wrong attribute names in the NRQL | run the query in the Query builder with `TIMESERIES 1 minute`; `FACET level` / `FACET namespace_name` |
| Issue opens, no push | workflow filter does not match (policy id) or channel payload invalid | **Workflows -> Test workflow**; **Destinations -> Test**; check `labels.policyIds` equals the id in `~/.nr-policy-id` |
| ntfy shows the push but with raw braces | payload template not rendered | channel property key must be `payload`; check the template in the UI |
| Fault burst prints `000` once and stops | app pod restarting | wait for Ready (`mssql-up` now waits), rerun |
| `Llm*` events missing (Lab 7) | AI monitoring flag not read, or openai SDK version not supported by the agent | `NEW_RELIC_LOG=stdout` shows the effective settings; `pip install -U newrelic openai` and rebuild |
| Admin login returns to /login | image built from an older `main` | `git pull` in ~/src/SimplCommerce, `redeploy.sh v2`; or Firefox |
| `git push` to Azure DevOps: "Cannot determine the organization name" | Git Credential Manager needs the URL path | `git config credential.useHttpPath true` |

## Appendix D - Maturity ladder

![Figure 7 - Maturity ladder.](assets/fig-best-practice-ladder.png)

| Level | Practice | Labs |
|---|---|---|
| 1. Observe | Agent on every workload (operator injection), logs and Kubernetes events on; tags (env, team, version); least-privilege keys in Secrets; watch the ingest budget | Steps 2-4 |
| 2. Detect | Fixed thresholds on day one; baselines for later; then NRQL conditions as code; prove every condition with a fault; run the NRQL before the condition | Labs 1, 5 |
| 3. Explain and route | An issue is a state, not a notification; destination + channel + workflow in code; let Incident Intelligence correlate, key on issue id; read what NRAI generates; never silence to stop noise | Labs 2, 3, 4 |
| 4. Predict and act | PREDICT on capacity and cost; notify, ticket, approve, self-heal behind the webhook; verify by the issue closing plus a health check; policies and workflows behind PR review (NerdGraph or Terraform) | Labs 2, 6, 7 |

## Appendix E - Reset

```bash
bash ~/nr-training/labs/06-faults/faults.sh mssql-up                        # between runs
kubectl delete ns simplcommerce && bash ~/nr-training/labs/02-app/build-and-deploy.sh v1   # app only (then rerun install-newrelic.sh to re-inject)
kind delete cluster --name nr-workshop                                       # full reset, then Steps 2-4 again (~10 min, images cached)
```

Workshop-only cleanup of WSL: `kind delete cluster --name nr-workshop`, `docker rmi simplcommerce:v1 ai-descgen:v1`, `rm -rf ~/src/SimplCommerce ~/nr-training ~/.nr-keys ~/.nr-policy-id`. Account: **Alerts -> Workflows / Destinations / Alert conditions**, delete the `nr-workshop*` objects; **API keys**, delete `nr-workshop-user` and `nr-workshop-license` (filter on `nr-workshop-`); the `nr-workshop` cluster entity disappears after retention.
