#!/usr/bin/env bash
# Module 12, part 4 — the Session 13 mini project.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
MP="$(cd "$(dirname "$0")/.." && pwd)/mini-project"
NS="-n miniproject"

kubectl delete namespace miniproject --ignore-not-found --wait=true >/dev/null 2>&1
sleep 3

hr "1. DEPLOY EVERYTHING"
run "kubectl apply -f $MP/manifests.yaml"
kubectl rollout status deployment/webapp $NS --timeout=300s
run "kubectl get all $NS"

hr "2. STORAGE — the PVC was dynamically provisioned and seeded"
run "kubectl get pvc $NS"
run "kubectl get pv | grep miniproject"
POD=$(kubectl get pods $NS -l app=webapp -o jsonpath='{.items[0].metadata.name}')
run "kubectl logs $POD $NS -c seed"
echo ">> The init container seeded the volume BEFORE nginx started."
run "kubectl exec $POD $NS -- cat /usr/share/nginx/html/index.html"

echo
echo "--- the data SURVIVES a full rollout ---"
echo "\$ kubectl exec ... -- append a marker, then restart the deployment"
kubectl exec "$POD" $NS -- sh -c "echo '<p>written at $(date +%H:%M:%S) by the first pod</p>' >> /usr/share/nginx/html/index.html"
run "kubectl exec $POD $NS -- cat /usr/share/nginx/html/index.html"
kubectl rollout restart deployment/webapp $NS >/dev/null
kubectl rollout status deployment/webapp $NS --timeout=300s
for i in $(seq 1 40); do
  n=$(kubectl get pods $NS -l app=webapp --no-headers | grep -c Terminating)
  [ "$n" = "0" ] && break; sleep 2
done
NEWPOD=$(kubectl get pods $NS -l app=webapp -o jsonpath='{.items[0].metadata.name}')
echo "new pod: $NEWPOD  (was $POD)"
run "kubectl exec $NEWPOD $NS -- cat /usr/share/nginx/html/index.html"
echo ">> A DIFFERENT pod, with the SAME data - it re-attached to the same PVC."

hr "3. PROBES"
run "kubectl get pods $NS -l app=webapp"
run "kubectl describe pod $NEWPOD $NS | grep -E 'Liveness|Readiness|Startup'"
run "kubectl get endpoints webapp $NS"
echo ">> The endpoint is present because the readiness probe passes."

hr "4. HPA — baseline"
for i in $(seq 1 24); do
  t=$(kubectl get hpa webapp $NS -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  [ -n "$t" ] && { echo "metrics available after $((i*5))s"; break; }
  sleep 5
done
run "kubectl get hpa webapp $NS"
run "kubectl top pods $NS"

hr "5. HPA — under load"
kubectl -n miniproject create deployment loadgen --image=busybox:1.36 -- sh -c 'while true; do wget -q -O- http://webapp >/dev/null 2>&1; done' >/dev/null
kubectl -n miniproject scale deployment loadgen --replicas=4 >/dev/null
kubectl rollout status deployment/loadgen $NS --timeout=300s
printf '%-8s %-10s %-10s %s\n' "TIME" "TARGET%" "REPLICAS" "CPU"
PEAK=1
for i in $(seq 1 16); do
  cur=$(kubectl get hpa webapp $NS -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  rep=$(kubectl get hpa webapp $NS -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
  cpu=$(kubectl top pods $NS -l app=webapp --no-headers 2>/dev/null | awk '{s+=$2} END {print s"m"}')
  printf '%-8s %-10s %-10s %s\n' "t+$((i*15))s" "${cur:-<none>}%" "${rep:-?}" "${cpu:-n/a}"
  [ -n "${rep:-}" ] && [ "${rep:-1}" -gt "$PEAK" ] && PEAK=$rep
  sleep 15
done
echo "peak replicas: $PEAK"
run "kubectl get hpa webapp $NS"
run "kubectl get pods $NS -l app=webapp"
run "kubectl describe hpa webapp $NS | sed -n '/Events:/,\$p' | head -8"

hr "6. ALL REPLICAS SHARE THE SAME PVC"
run "kubectl get pods $NS -l app=webapp -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --no-headers"
echo ">> NOTE: accessModes is ReadWriteOnce, which is per-NODE. These replicas"
echo ">> could only all mount it because local-path scheduled them onto the same"
echo ">> node. On a real cluster, scaling a Deployment that shares one RWO volume"
echo ">> will leave pods stuck in ContainerCreating on other nodes - this is why"
echo ">> stateful workloads use a StatefulSet with volumeClaimTemplates instead."

hr "7. TEAR DOWN"
kubectl -n miniproject delete deployment loadgen >/dev/null 2>&1
run "kubectl get all $NS"
