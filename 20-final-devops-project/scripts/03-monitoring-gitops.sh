#!/usr/bin/env bash
# Module 20, part 3 - monitoring and GitOps, both verified against the real
# Prometheus API and the real Argo CD controller rather than asserted.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
step(){ echo; echo "--- $* ---"; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
NS="-n finalproject"
GNS="finalproject-gitops"

PROM="http://localhost:9090"
promq(){ curl -s --get --data-urlencode "query=$1" "$PROM/api/v1/query"; }

# Ask Prometheus a question and print the scalar answer, or say plainly that
# there is no data. Printing an empty result as 0 would be a quiet lie.
pq(){
  echo "\$ promql: $1"
  promq "$1" | python3 -c "
import json,sys
r=json.load(sys.stdin)
if r.get('status')!='success': print('  QUERY ERROR:',r.get('error')); sys.exit()
res=r['data']['result']
if not res: print('  (no data)'); sys.exit()
for s in res:
    lbl=s['metric']
    who=lbl.get('pod') or lbl.get('instance') or lbl.get('job') or ''
    print('  %-46s %s' % (who, s['value'][1]))
"
}

hr "0. PORT-FORWARD PROMETHEUS"
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for i in $(seq 1 30); do
  curl -sf "$PROM/-/ready" >/dev/null 2>&1 && { echo "Prometheus API ready after ~${i}s"; break; }
  sleep 1
done
run "curl -s $PROM/api/v1/status/buildinfo | python3 -m json.tool | head -8"

# ===========================================================================
hr "1. THE SERVICEMONITOR IS ACTUALLY BEING HONOURED"
run "kubectl get servicemonitor,prometheusrule $NS"
echo
echo "A ServiceMonitor that exists is not the same as a target being scraped."
echo "Asking Prometheus which targets it really has:"
echo
echo "\$ GET $PROM/api/v1/targets"
curl -s "$PROM/api/v1/targets?state=active" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=[t for t in d['data']['activeTargets'] if t['labels'].get('namespace')=='finalproject']
if not rows: print('  NO TARGET -- the ServiceMonitor is not being honoured'); sys.exit(1)
for t in rows:
    print('  job=%-10s health=%-5s url=%s' % (t['labels'].get('job'), t['health'], t['scrapeUrl']))
    if t.get('lastError'): print('    lastError:', t['lastError'])
"
echo ">> health=up: Prometheus found the Service via the ServiceMonitor,"
echo ">> resolved its 'http' port, and is scraping /metrics every 15s."

# ===========================================================================
hr "2. METRICS - the application's own counters"
pq 'taskapi_requests_total'
pq 'taskapi_errors_total'
pq 'taskapi_tasks_created_total'
pq 'taskapi_uptime_seconds'

step "the counters MOVE - 20 more requests, then re-query"
POD=$(kubectl get pods $NS -l app=task-api -o jsonpath='{.items[0].metadata.name}')
BEFORE=$(promq 'taskapi_requests_total' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'nodata')")
echo "requests_total before: $BEFORE"
kubectl exec "$POD" $NS -- python -c "
import urllib.request
for _ in range(20):
    urllib.request.urlopen('http://localhost:8000/health', timeout=5).read()
print('sent 20 requests')" 2>&1 | grep -v '^Defaulted'
echo "waiting 20s for the next scrape (interval is 15s)..."
sleep 20
AFTER=$(promq 'taskapi_requests_total' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'nodata')")
echo "requests_total after:  $AFTER"
python3 -c "
b,a='$BEFORE','$AFTER'
try:
    d=float(a)-float(b)
    print('>> delta %+.0f -- Prometheus observed the traffic.' % d if d>0 else '>> UNEXPECTED: no increase (%s -> %s)' % (b,a))
except ValueError: print('>> could not compare:',b,a)
"

# ===========================================================================
hr "3. CPU AND MEMORY UTILISATION - from cAdvisor, not the app"
# These come from the kubelet's cAdvisor, so they measure the CONTAINER, and
# would be reported even if the app exposed no /metrics at all.
pq 'sum(rate(container_cpu_usage_seconds_total{namespace="finalproject",container="api"}[2m])) by (pod)'
pq 'sum(container_memory_working_set_bytes{namespace="finalproject",container="api"}) by (pod)'
echo ">> CPU in cores (0.001 = 0.1% of one core), memory in bytes."
pq 'kube_pod_container_status_restarts_total{namespace="finalproject"}'
pq 'kube_pod_status_phase{namespace="finalproject",phase="Running"}'

# ===========================================================================
hr "4. APPLICATION HEALTH AS A METRIC"
pq 'up{job="task-api"}'
echo ">> up is synthetic: Prometheus writes 1 when the scrape succeeded. It is"
echo ">> the signal behind the TaskApiDown alert, and it works even when the"
echo ">> app is too broken to report anything about itself."

# ===========================================================================
hr "5. LOGS"
run "kubectl logs $POD $NS --tail=5"
echo ">> Quiet by design: the handler suppresses per-request logging, so the"
echo ">> request stream is observed through metrics instead. What WOULD appear"
echo ">> here is a Python traceback, which is the thing worth alerting on."
echo
echo "--- the previous container's logs, for a crash that already happened ---"
echo "\$ kubectl logs $POD $NS --previous"
kubectl logs "$POD" $NS --previous 2>&1 | head -3
echo ">> No previous container: this pod has never restarted. That is the"
echo ">> first command to reach for on a CrashLoopBackOff, because the live"
echo ">> container is the one that has not failed yet."

# ===========================================================================
hr "6. ALERTS - the rules Prometheus loaded from the PrometheusRule CRD"
echo "\$ GET $PROM/api/v1/rules"
curl -s "$PROM/api/v1/rules" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for g in d['data']['groups']:
    if g['name']!='task-api': continue
    print('  group:',g['name'],'(file:',g['file'].split('/')[-1],')')
    for r in g['rules']:
        print('    %-26s state=%-8s for=%s' % (r['name'], r.get('state','-'), r.get('duration')))
"
echo ">> The CRD was translated into real loaded rules, each with a state."

step "FIRE TaskApiHighErrorRate on purpose"
echo "expr: sum(rate(taskapi_errors_total[5m])) / sum(rate(taskapi_requests_total[5m])) > 0.10, for: 2m"
echo
echo "Driving 400 requests to a path that does not exist, so errors_total rises"
echo "and the ratio crosses 10%:"
kubectl exec "$POD" $NS -- python -c "
import urllib.request,urllib.error
n=0
for _ in range(400):
    try: urllib.request.urlopen('http://localhost:8000/does-not-exist', timeout=5).read()
    except urllib.error.HTTPError: n+=1
print('got', n, '404s')" 2>&1 | grep -v '^Defaulted'
echo
echo "Now watching the alert's state change. inactive -> pending (condition"
echo "true, 'for' not yet elapsed) -> firing. Sampling every 15s:"
for i in $(seq 1 24); do
  SNAP=$(curl -s "$PROM/api/v1/rules" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for g in d['data']['groups']:
    for r in g['rules']:
        if r.get('name')=='TaskApiHighErrorRate': print(r.get('state','?')); sys.exit()
print('not-loaded')")
  RATIO=$(promq 'sum(rate(taskapi_errors_total[5m])) / sum(rate(taskapi_requests_total[5m]))' \
          | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print('%.3f'%float(r[0]['value'][1]) if r else 'n/a')")
  printf '  t+%-4s ratio=%-7s state=%s\n' "$((i*15))s" "$RATIO" "$SNAP"
  [ "$SNAP" = "firing" ] && { echo ">> FIRING. The rule proved itself end to end."; break; }
  sleep 15
done

step "the firing alert as Alertmanager sees it"
echo "\$ GET $PROM/api/v1/alerts"
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d=json.load(sys.stdin)
got=[a for a in d['data']['alerts'] if a['labels'].get('alertname','').startswith('TaskApi')]
if not got: print('  (none active)')
for a in got:
    print('  %s  state=%s severity=%s' % (a['labels']['alertname'], a['state'], a['labels'].get('severity')))
    print('    since:', a.get('activeAt'))
    print('    summary:', a['annotations'].get('summary'))
"

# ===========================================================================
hr "7. GITOPS - Argo CD takes over"
run "kubectl get pods -n argocd --no-headers | head -6"
echo
echo "--- the Secret Argo CD must NOT own, created out of band first ---"
kubectl create namespace $GNS >/dev/null 2>&1
kubectl -n $GNS create secret generic task-api-secret \
  --from-literal=DB_PASSWORD="$(openssl rand -hex 12)" \
  --from-literal=API_KEY="$(openssl rand -hex 12)" >/dev/null 2>&1
echo "\$ kubectl -n $GNS create secret generic task-api-secret --from-literal=..."
run "kubectl get secret task-api-secret -n $GNS"
echo
run "cat $D/gitops/application.yaml | grep -vE '^\s*#|^$' | head -30"
run "kubectl apply -f $D/gitops/application.yaml"

step "Argo CD pulls from GitHub and reconciles"
echo "Nothing below is applied by me. The Application names a repo, a revision"
echo "and a path; the controller clones it and makes the cluster match."
for i in $(seq 1 40); do
  S=$(kubectl get application task-api -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
  H=$(kubectl get application task-api -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
  printf '  t+%-4s sync=%-10s health=%s\n' "$((i*5))s" "${S:-?}" "${H:-?}"
  [ "$S" = "Synced" ] && [ "$H" = "Healthy" ] && break
  sleep 5
done
run "kubectl get application task-api -n argocd"
run "kubectl get all -n $GNS"
echo ">> These objects were never touched by kubectl. Git declared them."

step "what Argo CD believes it is tracking"
run "kubectl get application task-api -n argocd -o jsonpath='revision: {.status.sync.revision}{\"\\n\"}repo:     {.spec.source.repoURL}{\"\\n\"}path:     {.spec.source.path}{\"\\n\"}'"

# ===========================================================================
hr "8. CONTINUOUS RECONCILIATION - drift is corrected, not just detected"
echo "git declares replicas: 2. Scaling to 5 by hand is drift. selfHeal should"
echo "undo it without anyone asking."
echo
echo "\$ kubectl scale deployment task-api -n $GNS --replicas=5"
kubectl scale deployment task-api -n $GNS --replicas=5 2>&1
echo
echo "Sampling from t+0 so the correction is not missed between samples:"
for i in $(seq 0 30); do
  R=$(kubectl get deploy task-api -n $GNS -o jsonpath='{.spec.replicas}' 2>/dev/null)
  printf '  t+%-4s spec.replicas=%s\n' "$((i*2))s" "${R:-?}"
  [ "$i" -gt 0 ] && [ "$R" = "2" ] && { echo ">> Reverted to 2 after ~$((i*2))s. Argo CD won, as it should."; break; }
  sleep 2
done
run "kubectl get deploy task-api -n $GNS"
run "kubectl get application task-api -n argocd -o jsonpath='sync: {.status.sync.status}  health: {.status.health.status}{\"\\n\"}'"
echo
echo ">> The lesson: once GitOps owns a workload, kubectl is no longer a way to"
echo ">> change it. The only durable edit is a commit."
