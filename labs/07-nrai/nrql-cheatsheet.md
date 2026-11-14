# NRQL cheat sheet - what New Relic AI would generate (free fallback for Lab 4)

Paste into **Query your data** (Query builder). All queries assume `appName = 'SimplCommerce'` and cluster `nr-workshop`.

```sql
-- 1. error logs from the namespace, last hour (newrelic-logging attributes)
SELECT timestamp, pod_name, message FROM Log
WHERE namespace_name = 'simplcommerce' AND (level = 'ERROR' OR message LIKE '%fail:%')
SINCE 1 hour ago LIMIT 100

-- 2. the same as a chart
SELECT count(*) FROM Log
WHERE namespace_name = 'simplcommerce' AND (level = 'ERROR' OR message LIKE '%fail:%')
TIMESERIES 5 minutes SINCE 1 hour ago

-- 3. error rate per transaction, last 2 hours
SELECT percentage(count(*), WHERE error IS true) AS 'error %', count(*) AS requests
FROM Transaction WHERE appName = 'SimplCommerce' FACET name SINCE 2 hours ago

-- 4. issues and incidents (Incident Intelligence events)
SELECT timestamp, title, priority, event, conditionName, entity.name FROM NrAiIncident
WHERE event IN ('open', 'close') SINCE 1 day ago LIMIT 50
SELECT count(*) FROM NrAiIssue FACET event SINCE 1 day ago

-- 5. requests per minute today (the series Lab 6 predicts)
SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName = 'SimplCommerce' TIMESERIES SINCE today

-- 6. Kubernetes: pod restarts and waiting reasons in the namespace
SELECT max(restartCount) FROM K8sContainerSample WHERE namespaceName = 'simplcommerce' FACET podName TIMESERIES SINCE 1 hour ago
SELECT latest(reason), latest(status) FROM K8sContainerSample WHERE namespaceName = 'simplcommerce' FACET podName SINCE 30 minutes ago
SELECT timestamp, event.reason, event.message FROM InfrastructureEvent
WHERE event.involvedObject.namespace = 'simplcommerce' SINCE 1 hour ago LIMIT 50

-- 7. the SQL calls under a storefront request (distributed tracing spans)
SELECT name, db.statement, duration FROM Span
WHERE appName = 'SimplCommerce' AND db.system IS NOT NULL SINCE 30 minutes ago LIMIT 20

-- 8. errors with stack traces (Errors inbox data)
SELECT count(*) FROM TransactionError WHERE appName = 'SimplCommerce' FACET error.class, error.message SINCE 1 hour ago

-- 9. deployment markers (change tracking)
SELECT timestamp, version, description, user FROM Deployment WHERE entity.name = 'SimplCommerce' SINCE 1 day ago

-- 10. Lab 7: LLM calls recorded by AI Monitoring
SELECT request.model, response.usage.total_tokens, response.usage.prompt_tokens, response.usage.completion_tokens, duration
FROM LlmChatCompletionSummary WHERE appName = 'ai-descgen' SINCE 1 hour ago
SELECT role, content FROM LlmChatCompletionMessage WHERE appName = 'ai-descgen' SINCE 1 hour ago LIMIT 20

-- 11. what did Advanced Compute cost (paid accounts)
SELECT sum(CCU) FROM NrConsumption WHERE metric = 'AdvancedCCU' FACET productCapability SINCE 15 days ago
```

Attribute names to double-check on your account before the session (they differ by agent and chart version): `namespace_name` vs `namespaceName` on `Log`, `level` presence on .NET console logs, `event.involvedObject.namespace` on `InfrastructureEvent`.
