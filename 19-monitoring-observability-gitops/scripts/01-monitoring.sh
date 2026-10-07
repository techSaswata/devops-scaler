#!/usr/bin/env bash
# Module 19, part 1 — Monitoring and Observability (Session 20, Tasks 1 and 2).
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
NS="-n monitoring"

# Query Prometheus through a port-forward.
promq(){
  local q="$1"
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 19090:9090 >/dev/null 2>&1 &
  local pf=$!; sleep 3
  curl -s --get --data-urlencode "query=$q" http://localhost:19090/api/v1/query 2>/dev/null \
    | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for r in d['data']['result'][:8]:
        m=r['metric']; lbl=m.get('code') or m.get('pod') or m.get('instance') or m.get('__name__','')
        print(f\"    {lbl:<42} {float(r['value'][1]):.4f}\")
    if not d['data']['result']: print('    (no series)')
except Exception as e: print('    query failed:', e)
"
  { kill "$pf" && wait "$pf"; } 2>/dev/null
}

hr "1. THE MONITORING STACK"
run "helm list $NS"
run "kubectl get pods $NS"
echo ">> kube-prometheus-stack installs Prometheus, Grafana, Alertmanager,"
echo ">> node-exporter (node metrics) and kube-state-metrics (object metrics),"
echo ">> plus the Prometheus Operator that manages their configuration."
run "kubectl get svc $NS -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,PORT:.spec.ports[0].port --no-headers | head -8"

hr "2. METRICS — the first pillar"
echo "A workload instrumented with a /metrics endpoint:"
POD=$(kubectl get pods $NS -l app=metrics-app -o jsonpath='{.items[0].metadata.name}')
run "kubectl exec $POD $NS -- python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8000/metrics').read().decode())\" | head -18"
echo
echo ">> The Prometheus exposition format: HELP, TYPE, then name{labels} value."
echo ">> Four metric TYPES matter:"
echo ">>   counter    only goes up (requests, errors) - use rate() on it"
echo ">>   gauge      goes up and down (memory, queue depth, temperature)"
echo ">>   histogram  bucketed observations - gives you real percentiles"
echo ">>   summary    client-side quantiles; cannot be aggregated across pods"

hr "3. HOW PROMETHEUS IS TOLD TO SCRAPE IT"
run "kubectl get servicemonitor $NS"
run "kubectl get servicemonitor metrics-app $NS -o jsonpath='selector={.spec.selector.matchLabels}  path={.spec.endpoints[0].path}  interval={.spec.endpoints[0].interval}{\"\\n\"}'"
echo ">> You never edit prometheus.yml. You create a ServiceMonitor CRD and the"
echo ">> OPERATOR regenerates the config and reloads Prometheus. That is the"
echo ">> difference between the operator pattern and running Prometheus by hand."

hr "4. GENERATE SOME TRAFFIC TO MEASURE"
kubectl -n monitoring delete pod metrics-load --force --grace-period=0 >/dev/null 2>&1
kubectl -n monitoring run metrics-load --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://metrics-app:8000/ >/dev/null 2>&1; done' >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/metrics-load $NS --timeout=120s >/dev/null 2>&1
echo "load generator running; collecting for 90s..."
sleep 90

hr "5. QUERYING PROMETHEUS (PromQL)"
echo "\$ demo_requests_total          — raw counter, by status code"
promq 'demo_requests_total'
echo
echo "\$ rate(demo_requests_total[2m])  — per-second rate over 2 minutes"
promq 'rate(demo_requests_total[2m])'
echo
echo "\$ sum(rate(demo_requests_total{code=\"500\"}[2m])) / sum(rate(demo_requests_total[2m]))   — error ratio"
promq 'sum(rate(demo_requests_total{code="500"}[2m])) / sum(rate(demo_requests_total[2m]))'
echo
echo "\$ demo_request_latency_seconds  — average latency gauge"
promq 'demo_request_latency_seconds'
echo
echo ">> rate() on a COUNTER is the single most important PromQL idiom. The raw"
echo ">> counter only ever rises and resets on restart; rate() turns it into"
echo ">> 'per second right now' and handles the resets for you."

hr "6. CPU AND MEMORY — the metrics everyone asks for first"
echo "\$ container CPU, by pod"
promq 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="monitoring",pod=~"metrics-app.*"}[2m]))'
echo
echo "\$ container memory working set, by pod (bytes)"
promq 'sum by (pod) (container_memory_working_set_bytes{namespace="monitoring",pod=~"metrics-app.*"})'
echo
echo "\$ kubectl top pods  — the same data, via metrics-server"
run "kubectl top pods $NS | head -6"
echo ">> metrics-server and Prometheus are different systems. metrics-server"
echo ">> keeps ~1 minute in memory to drive the HPA; Prometheus stores history"
echo ">> for querying and alerting. Only one of them can answer 'what happened"
echo ">> at 3am last Tuesday'."

hr "7. APPLICATION HEALTH"
promq 'up{job="metrics-app"}'
echo ">> 'up' is synthesised by Prometheus itself: 1 if the scrape succeeded,"
echo ">> 0 if it failed. It is the cheapest possible liveness signal, and the"
echo ">> basis of nearly every 'service is down' alert."
run "kubectl get endpoints metrics-app $NS"

hr "8. ALERTS — the third thing monitoring is for"
run "kubectl get prometheusrule $NS"
run "kubectl get prometheusrule demo-alerts $NS -o jsonpath='{range .spec.groups[0].rules[*]}{.alert}  severity={.labels.severity}{\"\\n\"}{end}'"
echo
echo "--- which are actually FIRING right now? ---"
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 19090:9090 >/dev/null 2>&1 &
PF=$!; sleep 3
curl -s http://localhost:19090/api/v1/alerts 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
al=d['data']['alerts']
if not al: print('    (none firing)')
for a in al[:10]:
    print(f\"    {a['labels'].get('alertname',''):<28} state={a['state']:<10} severity={a['labels'].get('severity','')}\")
"
{ kill "$PF" && wait "$PF"; } 2>/dev/null
echo
echo ">> DemoHighErrorRate fires because the app deliberately returns 500 for"
echo ">> about 5% of requests, which is above the 2% threshold in the rule."
echo ">> DemoAppDown stays inactive because the app is up - showing the"
echo ">> difference between a rule that exists and a rule that is firing."

hr "9. LOGS — the second pillar"
run "kubectl logs -l app=metrics-app $NS --tail=3 --prefix"
echo
cat <<'NOTE'
  kubectl logs reads from the node's local files, which means:
    - logs vanish when the pod is deleted
    - you cannot search across pods, or across time
    - `--previous` gets you exactly ONE restart back

  That is why production ships logs off the node. The common stacks:
    Loki + Promtail       label-based, pairs naturally with Prometheus/Grafana
    ELK / OpenSearch      full-text search, heavier
    Fluent Bit -> S3      cheap long-term archive
  All three run as a DaemonSet - one collector per node, reading
  /var/log/containers (module 09 covers DaemonSets).
NOTE

hr "10. THE THREE PILLARS OF OBSERVABILITY"
cat <<'NOTE'

  METRICS   numeric, aggregated, cheap to store, cheap to query
            answers: IS something wrong? how much? for how long?
            Prometheus. Low cardinality - a label per user id will kill it.

  LOGS      discrete events with full context, expensive at volume
            answers: WHAT exactly happened to this one request?
            Loki, ELK. High cardinality is fine.

  TRACES    one request's path across every service, with timing per hop
            answers: WHERE in the chain did the latency come from?
            Jaeger, Tempo, OpenTelemetry. Usually sampled.

  THE DISTINCTION THAT MATTERS

    MONITORING asks questions you thought of in advance. You know CPU matters,
    so you build a CPU dashboard. It handles KNOWN failure modes.

    OBSERVABILITY is being able to ask questions you did NOT anticipate,
    without shipping new code. It handles UNKNOWN failure modes.

    A system with 500 dashboards and no way to ask "why is this ONE customer
    slow" is well monitored and poorly observable.

  HOW THEY CONNECT: an alert fires on a METRIC, you pivot to the TRACE for a
  slow request, then read the LOGS of the span that was slow. Correlation ids
  (trace_id) in log lines are what make that pivot possible.
NOTE

kubectl -n monitoring delete pod metrics-load --force --grace-period=0 >/dev/null 2>&1
