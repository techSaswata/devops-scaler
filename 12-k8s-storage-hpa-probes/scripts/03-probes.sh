#!/usr/bin/env bash
# Module 12, part 3 — probes, with the readiness/endpoint link actually proven.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete pod -l demo=probes --force --grace-period=0 >/dev/null 2>&1
kubectl delete svc probe-svc --ignore-not-found >/dev/null 2>&1
sleep 3

hr "1. ALL THREE PROBES ON A HEALTHY POD"
run "cat $M/07-probes.yaml | sed -n '/startupProbe/,\$p'"
run "kubectl apply -f $M/07-probes.yaml"
kubectl wait --for=condition=Ready pod/probes-demo --timeout=180s
run "kubectl get pod probes-demo"
run "kubectl describe pod probes-demo | grep -E 'Liveness|Readiness|Startup'"
echo
cat <<'NOTE'
  startupProbe    runs FIRST and ALONE. Liveness and readiness are suspended
                  while it runs. Lets a slow boot take time WITHOUT weakening
                  the liveness probe for the rest of the pod's life.
  readinessProbe  "can it serve traffic right now?"
                  Failing -> removed from Service endpoints. NOT restarted.
  livenessProbe   "is it wedged?"
                  Failing -> the kubelet KILLS and restarts the container.
NOTE

hr "2. READINESS GATES SERVICE ENDPOINTS — proven, not asserted"
run "kubectl apply -f $M/08-probe-failures.yaml"
echo
echo "--- probe-never-ready has a readiness probe pointing at a 404 ---"
sleep 25
run "kubectl get pod probe-never-ready"
echo ">> Running, but READY is 0/1, and RESTARTS is 0 - it was NOT restarted."
echo
echo "--- the Service selects it, but it is NOT in the endpoints ---"
run "kubectl get svc probe-svc"
run "kubectl get endpointslice -l kubernetes.io/service-name=probe-svc -o jsonpath='{range .items[*].endpoints[*]}addr={.addresses[0]} ready={.conditions.ready}{\"\\n\"}{end}'"
run "kubectl get endpoints probe-svc"
echo ">> ENDPOINTS is empty. The pod is alive and the label matches, but an"
echo ">> unready pod is never added - so it simply receives no traffic."
echo
echo "--- a pod spec is IMMUTABLE, so the probe itself cannot be edited ---"
echo "\$ kubectl patch pod probe-never-ready ... readinessProbe.httpGet.path=/"
kubectl patch pod probe-never-ready --type=json \
  -p='[{"op":"replace","path":"/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]' 2>&1 | head -3
echo ">> REJECTED. Pod specs are immutable apart from the container image,"
echo ">> tolerations and a couple of other fields. To change a probe you edit"
echo ">> the Deployment template and let it roll out a NEW pod."
echo
echo "--- so instead, make the probed PATH start existing ---"
echo "\$ kubectl exec probe-never-ready -- sh -c \"echo ok > /usr/share/nginx/html/not-a-real-path\""
kubectl exec probe-never-ready -- sh -c 'echo ok > /usr/share/nginx/html/not-a-real-path'
echo ">> The probe is unchanged; the URL it checks now returns 200 instead of 404."
for i in $(seq 1 20); do
  r=$(kubectl get pod probe-never-ready -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  [ "$r" = "true" ] && { echo "  became Ready after $((i*3))s"; break; }
  [ "$i" = "20" ] && echo "  still not ready after 60s"
  sleep 3
done
run "kubectl get pod probe-never-ready"
run "kubectl get endpoints probe-svc"
echo ">> The endpoint appeared the moment the pod went Ready. THIS is the"
echo ">> mechanism behind rolling updates with zero downtime: a new pod receives"
echo ">> no traffic until its readiness probe passes."

hr "3. A BAD LIVENESS PROBE RESTARTS A HEALTHY CONTAINER"
echo "nginx is fine. The probe points at a 404. Watch the restart count:"
printf '%-8s %-12s %s\n' "TIME" "STATUS" "RESTARTS"
for i in $(seq 1 8); do
  s=$(kubectl get pod probe-bad-liveness --no-headers 2>/dev/null | awk '{print $3}')
  r=$(kubectl get pod probe-bad-liveness --no-headers 2>/dev/null | awk '{print $4}')
  printf '%-8s %-12s %s\n' "t+$((i*15))s" "${s:-?}" "${r:-?}"
  sleep 15
done
run "kubectl describe pod probe-bad-liveness | sed -n '/Events:/,\$p' | head -10"
echo ">> 'Liveness probe failed: HTTP probe failed with statuscode: 404'"
echo ">> followed by 'Killing container'. The application never had a problem."
echo
cat <<'NOTE'
  RULE OF THUMB: liveness GENEROUS, readiness STRICT.

    A liveness probe's remedy is a KILL, so it should only fail when the process
    is genuinely unrecoverable - a deadlock, not a slow dependency.

    A readiness probe's remedy is to stop sending traffic, which is cheap and
    reversible, so it can be strict and check dependencies.

  THE CLASSIC OUTAGE: a liveness probe that calls a shared database. The database
  gets slow, EVERY pod's liveness probe fails at once, Kubernetes restarts the
  entire fleet simultaneously, and a slow dependency becomes a total outage.
NOTE

hr "4. CLEAN UP"
run "kubectl delete pod -l demo=probes --force --grace-period=0"
kubectl delete svc probe-svc --ignore-not-found >/dev/null 2>&1
