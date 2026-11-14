#!/usr/bin/env bash
# Fault injection for the Incident Intelligence lab. DEMO CLUSTER ONLY. Every fault has a rollback.
# Usage: bash faults.sh <mssql-down|mssql-up|500s|throw|crashloop|rollback-crashloop|imagepull|rollback-imagepull> [seconds]
#   500s and throw take an optional duration (default 150 s, one request every 2 s). Keep bursts above ~2 min so the
#   alert events stay open long enough for the issue to ACTIVATE, merge with the other condition and feed a compound alert.
set -euo pipefail
NS=simplcommerce
case "${1:-}" in
  mssql-down)   # cascading failure: ~2 min of real 500s, then the app crash-loops (it reads config from the DB at boot)
    kubectl -n $NS scale deploy/mssql --replicas=0
    echo "SQL Server stopped. Watch k9s: within ~1 min the app's background job hits SqlException and the process exits -> CrashLoopBackOff. K8s events within a minute; 'Signal lost' alert event ~4.5 min, issue + push ~5.5 min (error-rate/log events first only if the app survives longer)." ;;
  mssql-up)
    kubectl -n $NS scale deploy/mssql --replicas=1
    kubectl -n $NS rollout status deploy/mssql --timeout=300s
    kubectl -n $NS delete pod -l app=$NS      # reset the crash backoff so recovery is immediate
    kubectl -n $NS rollout status deploy/$NS --timeout=300s   # wait for the new app pod, so a fault fired right after this works
    echo "SQL Server back. Issues should close themselves once the signal is back under threshold (plus the condition's recovery window)." ;;
  500s)         # clean 5xx burst, app stays up (DemoFaults endpoint, on by default)
    for i in $(seq 1 $(( ${2:-150} / 2 ))); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/api/demo/status/500 || true; sleep 2; done; echo ;;   # || true: set -e must not stop the burst on one refused connection
  throw)        # real unhandled exception with a stack trace (Triage Inbox + Lab 5 log condition)
    for i in $(seq 1 $(( ${2:-150} / 2 ))); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/api/demo/throw || true; sleep 2; done; echo ;;
  crashloop)    # true CrashLoopBackOff -> K8sContainerSample restartCount climbs, BackOff events
    kubectl -n $NS set env deployment/$NS ConnectionStrings__DefaultConnection="Server=nonexistent;Database=x;User Id=sa;Password=x;TrustServerCertificate=true"
    echo "App will die at boot; restart counter climbs." ;;
  rollback-crashloop)
    kubectl -n $NS rollout undo deployment/$NS
    kubectl -n $NS rollout status deployment/$NS --timeout=600s ;;
  imagepull)    # ImagePullBackOff -> pod never Ready, different shape from a restart loop
    kubectl -n $NS set image deployment/$NS web=simplcommerce:does-not-exist ;;
  rollback-imagepull)
    kubectl -n $NS rollout undo deployment/$NS
    kubectl -n $NS rollout status deployment/$NS --timeout=600s ;;
  *) echo "usage: $0 <mssql-down|mssql-up|500s|throw|crashloop|rollback-crashloop|imagepull|rollback-imagepull>"; exit 1 ;;
esac
