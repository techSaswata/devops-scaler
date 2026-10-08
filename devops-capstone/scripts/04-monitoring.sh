#!/usr/bin/env bash
# M9 — Prometheus scraping ClinicFlow, and Grafana showing it.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
NS=clinicflow
PROM=http://localhost:9090
promq(){ curl -s --get --data-urlencode "query=$1" "$PROM/api/v1/query"; }
pq(){
  echo "\$ promql: $1"
  promq "$1" | python3 -c "
import json,sys
r=json.load(sys.stdin)
if r.get('status')!='success': print('  QUERY ERROR:', r.get('error')); sys.exit()
res=r['data']['result']
if not res: print('  (no data)'); sys.exit()
for s in res[:8]:
    m=s['metric']
    who=m.get('pod') or m.get('status') or m.get('instance') or m.get('job') or ''
    print('  %-50s %s' % (who, s['value'][1]))"
}

hr "1. INSTALL kube-prometheus-stack"
run "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>&1 | tail -1"
run "helm repo update 2>&1 | tail -1"
runfull "helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f $D/monitoring/prometheus-values.yaml \
  --wait --timeout 15m"
runfull "kubectl get pods -n monitoring"

hr "2. ALERT RULES"
runfull "kubectl apply -f $D/monitoring/alert-rules.yaml"
runfull "kubectl get prometheusrule,servicemonitor -n $NS"

hr "3. PORT-FORWARD PROMETHEUS"
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
PF=$!
kubectl -n monitoring port-forward svc/monitoring-grafana 3001:80 >/dev/null 2>&1 &
GF=$!
trap 'kill $PF $GF 2>/dev/null' EXIT
for i in $(seq 1 40); do
  curl -sf "$PROM/-/ready" >/dev/null 2>&1 && { echo "Prometheus API ready after ~${i}s"; break; }
  sleep 2
done

hr "4. IS THE APPLICATION ACTUALLY A TARGET?"
echo "A ServiceMonitor that EXISTS and a target that is SCRAPED are different"
echo "claims. Only the second one matters, so ask Prometheus directly."
echo
echo "\$ GET $PROM/api/v1/targets"
curl -s "$PROM/api/v1/targets?state=active" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=[t for t in d['data']['activeTargets'] if t['labels'].get('namespace')=='clinicflow']
if not rows:
    print('  NO TARGET -- the ServiceMonitor is not being honoured'); sys.exit(1)
for t in rows:
    print('  job=%-34s health=%-6s %s' % (t['labels'].get('job'), t['health'], t['scrapeUrl']))
    if t.get('lastError'): print('    lastError:', t['lastError'])"

hr "5. APPLICATION METRICS"
pq 'up{namespace="clinicflow"}'
pq 'sum by (status) (http_requests_total{namespace="clinicflow"})'
pq 'sum(rate(http_requests_total{namespace="clinicflow"}[2m]))'

hr "6. THE COUNTERS MOVE"
LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
BEFORE=$(promq 'sum(http_requests_total{namespace="clinicflow"})' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'nodata')")
echo "http_requests_total before: $BEFORE"
echo "sending 60 requests through the ingress..."
for i in $(seq 1 60); do
  curl -s -o /dev/null --max-time 5 -H 'Host: clinicflow.local' "http://$LB/api/appointments/stats"
done
echo "waiting 20s for the next 15s scrape..."
sleep 20
AFTER=$(promq 'sum(http_requests_total{namespace="clinicflow"})' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'nodata')")
echo "http_requests_total after:  $AFTER"
python3 -c "
b,a='$BEFORE','$AFTER'
try:
    d=float(a)-float(b)
    print('>> delta %+.0f -- Prometheus observed real traffic.' % d if d>0 else '>> UNEXPECTED: no increase (%s -> %s)'%(b,a))
except ValueError: print('>> could not compare:', b, a)"

hr "7. LATENCY, FROM A HISTOGRAM"
pq 'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="clinicflow"}[5m])) by (le))'
echo ">> p95 in seconds. A histogram, not an average: averages hide the tail,"
echo ">> and the tail is what users actually notice."

hr "8. CPU AND MEMORY FROM cADVISOR (not from the app)"
pq 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="clinicflow",container!=""}[2m]))'
pq 'sum by (pod) (container_memory_working_set_bytes{namespace="clinicflow",container!=""})'
echo ">> These are reported by the kubelet, so they exist even when the"
echo ">> application is too broken to describe itself."

hr "9. ALERT RULES LOADED"
echo "\$ GET $PROM/api/v1/rules"
curl -s "$PROM/api/v1/rules" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for g in d['data']['groups']:
    if g['name']!='clinicflow': continue
    print('  group:', g['name'])
    for r in g['rules']:
        print('    %-28s state=%-9s for=%s' % (r['name'], r.get('state','-'), r.get('duration')))"
echo ">> The CRD became real loaded rules, each with a state."

hr "10. GRAFANA"
for i in $(seq 1 40); do
  curl -sf http://localhost:3001/api/health >/dev/null 2>&1 && { echo "Grafana API ready after ~${i}s"; break; }
  sleep 2
done
runfull "curl -s http://localhost:3001/api/health"
echo
# Read the password the chart generated. Nothing credential-shaped is written
# down here, which is what the secret scanner is actually asking for.
GPASS=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d)
echo "--- import the ClinicFlow dashboard ---"
curl -s -X POST "http://admin:${GPASS}@localhost:3001/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c "
import json
d=json.load(open('$D/monitoring/grafana-dashboard.json'))
print(json.dumps({'dashboard':d,'overwrite':True,'folderId':0}))")" \
  | python3 -c "import json,sys;r=json.load(sys.stdin);print('  imported:',r.get('slug'),'status:',r.get('status','ok'),'url:',r.get('url'))"
echo
echo "--- does the datasource actually answer? ---"
curl -s -u "admin:${GPASS}" "http://localhost:3001/api/datasources" \
  | python3 -c "import json,sys;[print('  %-18s %s'%(d['name'],d['type'])) for d in json.load(sys.stdin)]"
